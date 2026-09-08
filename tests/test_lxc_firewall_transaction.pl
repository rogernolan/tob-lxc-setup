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
        directory => $dir, candidate => 'NEW', desired_nic => 'firewall=1',
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
done_testing();
