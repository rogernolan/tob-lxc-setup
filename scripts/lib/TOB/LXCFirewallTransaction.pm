package TOB::LXCFirewallTransaction;
use strict;
use warnings;
use JSON::PP;
use Fcntl qw(:DEFAULT :flock);
use IO::Handle;
use File::Path qw(make_path);
my $json = JSON::PP->new->canonical;
sub same { $json->encode($_[0]) eq $json->encode($_[1]) }
sub save {
    my ($path, $state) = @_;
    my $tmp = "$path.tmp.$$";
    sysopen(my $f, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) or die "$tmp: $!\n";
    print $f $json->encode($state) or die "write recovery snapshot: $!\n";
    $f->flush or die "flush recovery snapshot: $!\n";
    $f->sync or die "sync recovery snapshot: $!\n";
    close $f or die "close recovery snapshot: $!\n";
    rename($tmp,$path) or die "publish recovery snapshot: $!\n";
}
sub apply {
    my (%arg) = @_;
    my $dir = $arg{directory};
    make_path($dir, {mode=>0700});
    sysopen(my $lock, "$dir/lock", O_WRONLY|O_CREAT, 0600) or die "open lock: $!\n";
    flock($lock,LOCK_EX|LOCK_NB) or die "another firewall operation is running\n";
    my $pending = "$dir/pending.json";
    die "unresolved transaction at $pending; recover before retrying\n" if -e $pending;
    my $before = $arg{capture}->();
    my $desired_nic = ref($arg{desired_nic}) eq 'CODE'
        ? $arg{desired_nic}->($before) : $arg{desired_nic};
    my $desired = {%$before, policy=>$arg{candidate}, nic=>$desired_nic};
    my $baseline = $arg{validate}->($before);
    my $expected = $arg{validate}->($desired);
    die "configuration changed during validation\n" unless same($before,$arg{capture}->());
    if (same($before,$desired)) {
        $arg{verify}->($desired,$expected);
        return 'unchanged';
    }
    save($pending,{before=>$before, desired=>$desired});
    my $touched = 0;
    my $ok = eval {
        local $SIG{INT} = local $SIG{TERM} = local $SIG{HUP} = sub {die "operation interrupted\n"};
        die "configuration changed before activation\n" unless same($before,$arg{capture}->());
        # Track attempted operations before invoking them: a command may fail
        # after completing its write, so rollback inspects current state.
        $touched = 1;
        $arg{publish}->($desired->{policy}) unless same($before->{policy},$desired->{policy});
        $arg{set_nic}->($desired->{nic}) unless same($before->{nic},$desired->{nic});
        die "configuration changed after activation\n" unless same($desired,$arg{capture}->());
        $arg{validate}->($desired);
        $arg{verify}->($desired,$expected);
        save("$dir/previous.json",{before=>$before, desired=>$desired});
        unlink($pending) or die "clear pending transaction: $!\n";
        1;
    };
    return 'applied' if $ok;
    my $failure = $@;
    my $recovered = eval {
        local $SIG{INT} = local $SIG{TERM} = local $SIG{HUP} = 'IGNORE';
        if ($touched) {
            my $now = $arg{capture}->();
            # Only states produced by our two writes are safe to roll back.
            my $owned = {%$now, policy=>$before->{policy}, nic=>$before->{nic}};
            die "external context edit\n" unless same($owned,$before);
            for my $key ('policy','nic') {
                die "external $key edit\n" unless same($now->{$key},$before->{$key}) || same($now->{$key},$desired->{$key});
            }
            $arg{publish}->($before->{policy}) unless same($now->{policy},$before->{policy});
            $arg{set_nic}->($before->{nic}) unless same($now->{nic},$before->{nic});
            die "original state not restored\n" unless same($before,$arg{capture}->());
            $arg{verify}->($before,$baseline);
        }
        unlink($pending) or die "clear pending transaction: $!\n";
        1;
    };
    die "$failure\nrecovery required: $pending\n$@" unless $recovered;
    die "$failure\nOriginal configuration restored.\n";
}
1;
