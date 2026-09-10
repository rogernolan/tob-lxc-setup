#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../scripts/lib";
BEGIN { eval { require TOB::LXCFirewallTransaction; 1 } or die "FAIL: transaction engine missing\n"; }
use JSON::PP;
my ($state, @events, $fail_at, $external);
my $json = JSON::PP->new->canonical;
sub clone { decode_json($json->encode($_[0])) }
sub execute {
    my ($dir) = @_;
    TOB::LXCFirewallTransaction::apply(
        directory => $dir, lock_path => "$dir/host.lock", candidate => 'NEW', desired_nic => 'firewall=1',
        capture => sub { push @events, 'capture'; return clone($state) },
        validate => sub { my ($s) = @_; push @events, "validate:" . ($s->{policy}//'ABSENT');
            die "validation failed\n" if $fail_at eq 'validate' && ($s->{policy}//'') eq 'NEW';
            if ($external && ($s->{policy}//'') eq 'NEW') { $state->{context} = 'CHANGED'; }
            return $s->{policy}; },
        publish => sub { my ($p) = @_; push @events, "publish:" . ($p//'ABSENT');
            die "publication failed\n" if $fail_at eq 'publish' && ($p//'') eq 'NEW';
            $state->{policy} = $p; },
        set_nic => sub { my ($n) = @_; push @events, "nic:$n";
            die "NIC failed\n" if $fail_at eq 'nic' && $n eq 'firewall=1';
            $state->{nic} = $n; },
        verify => sub { my ($s) = @_; push @events, "verify:" . ($s->{policy}//'ABSENT');
            if ($fail_at eq 'verify' && ($s->{policy}//'') eq 'NEW') { die "convergence failed\n"; }
            if ($fail_at eq 'rollback' && ($s->{policy}//'') eq 'NEW') { $state->{policy} = 'EXTERNAL'; die "convergence failed\n"; }
            return 1; },
    );
}
sub reset_case { $state={policy=>'OLD',nic=>'firewall=0',context=>'SAME'}; @events=(); $fail_at=''; $external=0; }
reset_case();
my $dir=tempdir(CLEANUP=>1);
my $result=execute($dir);
is($result, 'applied', 'success');
is_deeply($state,{policy=>'NEW',nic=>'firewall=1',context=>'SAME'},'desired state');
my $log=join(',',@events);
like($log, qr/validate:NEW.*publish:NEW.*nic:firewall=1.*verify:NEW/, 'validate before activation');
ok(-f "$dir/previous.json", 'recovery snapshot retained');
ok(!-e "$dir/pending.json", 'completed transaction cleared');
@events=();
is(execute($dir), 'unchanged', 'idempotent rerun');
unlike(join(',',@events),qr/publish:|nic:/,'idempotence avoids mutations');
for my $point ('validate','publish','nic','verify') {
    reset_case(); $fail_at=$point; my $d=tempdir(CLEANUP=>1);
    eval {execute($d)}; ok($@, "$point fails");
    is_deeply($state,{policy=>'OLD',nic=>'firewall=0',context=>'SAME'},"$point restores original");
    ok(!-e "$d/pending.json", "$point leaves no unresolved transaction");
}
reset_case(); $external=1; my $d=tempdir(CLEANUP=>1);
eval {execute($d)}; like($@,qr/changed/,'context change detected');
unlike(join(',',@events),qr/publish:|nic:/,'context change never activates');
reset_case(); $fail_at='rollback'; $d=tempdir(CLEANUP=>1);
eval {execute($d)}; like($@,qr/recovery required/,'rollback conflict requires manual recovery');
is($state->{policy},'EXTERNAL','external edit not overwritten');
ok(-f "$d/pending.json", 'unresolved transaction retained');
eval {execute($d)}; like($@,qr/unresolved/,'rerun refuses pending recovery');
reset_case(); $state->{policy}=undef; $fail_at='nic'; $d=tempdir(CLEANUP=>1);
eval {execute($d)}; ok($@,'failure with previously absent policy');
ok(!defined($state->{policy}), 'rollback restores file absence');
reset_case(); $d=tempdir(CLEANUP=>1); execute($d);
is((stat("$d/previous.json"))[2] & 0777,0600,'recovery snapshot is private');
# A second guest must be refused before even capturing shared context while
# another process is in a transaction. Pipes avoid timing-dependent sleeps.
my $host = tempdir(CLEANUP=>1);
pipe(my $ready_read, my $ready_write) or die $!;
pipe(my $release_read, my $release_write) or die $!;
my $pid = fork(); die "fork: $!" unless defined $pid;
if (!$pid) {
    close $ready_read; close $release_write;
    my $first = 1;
    my $guest = {policy=>'OLD',nic=>'firewall=1',context=>'SAME'};
    eval {
        TOB::LXCFirewallTransaction::apply(
            directory=>"$host/105", lock_path=>"$host/lock",
            candidate=>'NEW', desired_nic=>'firewall=1',
            capture=>sub {
                if ($first) {
                    $first=0; syswrite($ready_write, "R");
                    sysread($release_read, my $byte, 1) == 1 or die 'release pipe';
                }
                return clone($guest);
            },
            validate=>sub { return 1 },
            publish=>sub {$guest->{policy}=$_[0]},
            set_nic=>sub {$guest->{nic}=$_[0]},
            verify=>sub {return 1},
        );
    };
    my $error=$@;
    warn $error if $error;
    require POSIX; POSIX::_exit($error ? 1 : 0);
}
close $ready_write; close $release_read;
sysread($ready_read, my $byte, 1) == 1 or die 'child did not start';
my $captures=0;
my $other={policy=>'OLD',nic=>'firewall=1',context=>'SAME'};
my %other_args=(
    directory=>"$host/107",lock_path=>"$host/lock",
    candidate=>'NEW',desired_nic=>'firewall=1',
    capture=>sub {$captures++;return clone($other)},
    validate=>sub {return 1},publish=>sub {$other->{policy}=$_[0]},
    set_nic=>sub {$other->{nic}=$_[0]},verify=>sub {return 1},
);
eval {TOB::LXCFirewallTransaction::apply(%other_args)};
like($@,qr/another firewall operation/,'different guest refused while host lock held');
is($captures,0,'contending guest does not capture or mutate context');
ok(!-e "$host/107/pending.json",'contention leaves no pending recovery');
syswrite($release_write,"R"); close $release_write;
waitpid($pid,0); is($? >> 8,0,'first guest completes');
is(TOB::LXCFirewallTransaction::apply(%other_args),'applied','second guest succeeds after lock released');
ok(-f "$host/105/previous.json" && -f "$host/107/previous.json",'recovery snapshots remain per guest');
close $ready_read;
done_testing();
