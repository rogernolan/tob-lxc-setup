package TOB::LXCFirewallTarget;
use strict;
use warnings;

sub select_guest {
    my ($data, $vmid, $nic) = @_;
    my $guest = $data->{lxc}->{$vmid} // die "target is not a local LXC\n";
    die "guest locked\n" if $guest->{lock};
    my @nics = grep { /^net[0-9]+$/ } keys %$guest;
    die "requires exactly one NIC\n" unless @nics == 1;
    die "selected NIC does not match guest\n" unless $nics[0] eq $nic;
    return $guest;
}

1;
