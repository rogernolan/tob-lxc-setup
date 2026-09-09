#!/usr/bin/perl
# Run on Proxmox: perl tests/test_lxc_firewall_native.pl scripts/lxc-firewall-validate
use strict;
use warnings;
use File::Temp qw(tempdir);
use JSON::PP;
my $validator = shift or die "validator path required\n";
-f $validator or die "FAIL: native validator missing\n";
my $dir = tempdir('tob-fw-native-XXXXXX', TMPDIR => 1, CLEANUP => 1);
sub write_file { my ($name, $text) = @_; open my $f, '>', "$dir/$name" or die $!; print $f $text; close $f or die $!; }
write_file('cluster.fw', "[OPTIONS]\nenable: 1\npolicy_in: DROP\npolicy_out: ACCEPT\n[ALIASES]\nlocal_network 192.168.68.0/22\n");
write_file('host.fw', "[OPTIONS]\n");
write_file('vmdata.json', encode_json({qemu => {}, lxc => {105 => {net0 => 'name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:68:9F:3B,ip=dhcp,type=veth'}}, corosync => {}}));
my $prefix = "[OPTIONS]\nenable: 1\npolicy_in: DROP\npolicy_out: ACCEPT\ndhcp: 1\n[RULES]\n";
sub invoke {
    open my $pipe, '-|', $^X, $validator, $dir, 105, 'net0' or die $!;
    local $/; my $out = <$pipe>; close $pipe;
    return ($? >> 8, $out);
}
my $count = 0;
sub check { my ($ok, $message) = @_; die "FAIL: $message\n" unless $ok; $count++; }
write_file('105.fw', $prefix . "IN ACCEPT -source 192.168.68.0/22 -p tcp -dport 22\nIN ACCEPT -source 192.168.68.0/22 -p tcp -dport 445\nIN ACCEPT -source 192.168.68.0/22 -p udp -dport 5353\n");
my ($status, $out) = invoke();
check($status == 0, 'valid policy must compile');
my $rules = decode_json($out);
my $v4 = join("\n", @{$rules->{ipv4}});
my $v6 = join("\n", @{$rules->{ipv6}});
check($v4 =~ /-s 192\.168\.68\.0\/22 .*--dport 445 .*ACCEPT/, 'scoped SMB allow compiled');
check(index($v4, '--dport 445') < index($v4, '-j PVEFW-Drop'), 'SMB allow precedes default drop');
check($v4 =~ /--dport 68 .*ACCEPT/, 'DHCP response preserved');
check($v4 =~ /-s 192\.168\.68\.0\/22 .*--dport 5353 .*ACCEPT/, 'LAN mDNS allowance compiles');
check($rules->{signatures}->{ipv4}->{'veth105i0-IN'}, 'native chain signature returned');
check($v6 !~ /--dport (22|445)\b/, 'baseline has no IPv6 service allowance');
write_file('105.fw', $prefix . "IN ACCEPT -source 192.168.68.0/22 -p tcp -dport 445\nIN ACCEPT -source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport 22\nIN ACCEPT -source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport 445\nIN ACCEPT -source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport 8080\n");
($status, $out) = invoke();
check($status == 0, 'dual-stack service rules compile');
$rules = decode_json($out);
$v6 = join("\n", @{$rules->{ipv6}});
check($v6 =~ /-s fdbc:54c7:7b7e:4bdd::\/64 .*--dport 22 .*ACCEPT/, 'IPv6 SSH source constrained to observed subnet');
check($v6 =~ /-s fdbc:54c7:7b7e:4bdd::\/64 .*--dport 445 .*ACCEPT/, 'SMB allows trusted IPv6 subnet');
check($v6 =~ /-s fdbc:54c7:7b7e:4bdd::\/64 .*--dport 8080 .*ACCEPT/, 'application allows trusted IPv6 subnet');
check($v6 !~ /--dport (137|138|139)\b.*ACCEPT/, 'no IPv6 NetBIOS allows');
for my $bad ('IN ACCEPT -p tcp -dport 999999', 'IN ACCEPT -source nonsense -p tcp -dport 22', 'IN ACCEPT -p tcp -dport 22 garbage', 'not a rule') {
    write_file('105.fw', $prefix . "$bad\n");
    ($status, $out) = invoke();
    check($status != 0, "reject malformed candidate: $bad");
}
write_file('105.fw', "[OPTIONS]\nenable: 0\npolicy_in: ACCEPT\npolicy_out: ACCEPT\n");
($status, $out) = invoke();
check($status == 0, 'unrestricted compiles');
$rules = decode_json($out);
check(!@{$rules->{ipv4}} && !@{$rules->{ipv6}}, 'unrestricted generates no guest chains');
write_file('cluster.fw', "[OPTIONS]\nenable: 0\n");
($status, $out) = invoke();
check($status != 0, 'disabled cluster cannot produce false validation success');
print "PASS: $count native compiler assertions\n";
