package Plugins::Container::Docker::Network::Stop;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw (dclone);

use Plugins::Container::Docker::Network::IPT qw(remove_fw);

our @EXPORT_OK = qw(create_network_stop_script);

##########################################################################

sub create_network_stop_script ( $container_name, $interface_name ) {

    my @stop_network = (
        "ip link del $interface_name\_h > /dev/null 2>&1 || true",
        "ip link del $interface_name\_c > /dev/null 2>&1 || true",
        remove_fw($container_name)    #
    );

    return \@stop_network;
}

1;
