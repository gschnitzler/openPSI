package Plugins::Container::Docker::Network::Start;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw (dclone);

use Plugins::Container::Docker::Network::IPT qw(add_forward_entries);

our @EXPORT_OK = qw(create_network_start_script);

##########################################################################

sub create_network_start_script ( $config, $host_network, $docker_network ) {

    my $container_name      = $config->{NAME};
    my $ports               = $config->{NETWORK}->{FORWARD};
    my $container_interface = $config->{NETWORK}->{INTERFACE};
    my $ips                 = dclone( $config->{NETWORK}->{IP} );
    my $external_interface  = $host_network->{INTERFACE};
    my $docker_interface    = $docker_network->{INTERFACE};
    my $docker_gw           = $docker_network->{ADDRESS};
    my @networking_script   = ();

    # the pid of the started container is only available after it started. thus, the § to set at runtime
    push(
        @networking_script,
        add_forward_entries( $container_name, $ips, dclone($host_network), $ports, $external_interface ),    #fw rules, if required
        'mkdir -p /var/run/netns',
        'until ln -s /proc/§pid/ns/net /var/run/netns/§pid; do sleep 1; done',                             # setting host netlink
        "ip link add $container_interface\_h type veth peer name $container_interface\_c",                   # adding host netlink
        "ip link set $container_interface\_h master $docker_interface",                                      # adding container host if to bridge
        "ip link set $container_interface\_h up",                                                            # bringing up host if
        "ip link set $container_interface\_c netns §pid",                                                   # adding container link
        "ip netns exec §pid ip link set dev $container_interface\_c name $external_interface",              # config container if
        "ip netns exec §pid ip link set $external_interface up",                                            # bringing up container if
    );

    # adding container ip, add main first
    my $mainip = delete( $ips->{main} );
    push( @networking_script, "ip netns exec §pid ip addr add $mainip/24 dev $external_interface" );

    foreach my $k ( keys $ips->%* ) {
        my $v = $ips->{$k};
        push( @networking_script, "ip netns exec §pid ip addr add $v/24 dev $external_interface" );
    }

    push( @networking_script, "ip netns exec §pid ip route add default via $docker_gw" );                   # adding container route

    return \@networking_script;
}

1;
