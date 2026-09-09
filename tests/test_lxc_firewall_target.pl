#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../scripts/lib";
BEGIN {eval {require TOB::LXCFirewallTarget;1} or die "FAIL: generic target validation missing\n";}
my $data={lxc=>{107=>{hostname=>'tob-dev',net3=>'bridge=vmbr0'}},qemu=>{108=>{}}};
is(TOB::LXCFirewallTarget::select_guest($data,107,'net3')->{hostname},'tob-dev','generic local guest accepted');
eval {TOB::LXCFirewallTarget::select_guest($data,108,'net0')};like($@,qr/local LXC/,'QEMU refused');
eval {TOB::LXCFirewallTarget::select_guest($data,109,'net0')};like($@,qr/local LXC/,'nonlocal/missing refused');
eval {TOB::LXCFirewallTarget::select_guest($data,107,'net0')};like($@,qr/selected NIC/,'wrong NIC refused');
$data->{lxc}->{107}->{lock}='migrate';
eval {TOB::LXCFirewallTarget::select_guest($data,107,'net3')};like($@,qr/locked/,'migration refused');
delete $data->{lxc}->{107}->{lock};$data->{lxc}->{107}->{net0}='bridge=vmbr1';
eval {TOB::LXCFirewallTarget::select_guest($data,107,'net3')};like($@,qr/exactly one/,'multiple NICs refused');
done_testing();
