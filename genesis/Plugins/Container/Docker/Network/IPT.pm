package Plugins::Container::Docker::Network::IPT;

use ModernStyle;
use Exporter qw(import);
use Storable qw(dclone);

use InVivo qw(kexists);

our @EXPORT_OK = qw(add_fw add_forward_entries remove_fw);

################################################################

# create IP mapping
sub _get_ipmap ( $container_ips, $host_ips ) {

    my $ipmap = {
        main => {
            host_ip      => $host_ips->{ADDRESS},
            container_ip => $container_ips->{main}
        }
    };

    foreach my $name ( keys $container_ips->%* ) {

        next if ( $name eq 'main' );
        die "ERROR: no host IP name found for $name" unless ( kexists( $host_ips, 'ADDITIONAL', $name ) );
        $ipmap->{$name} = { host_ip => $host_ips->{ADDITIONAL}->{$name}->{ADDRESS}, container_ip => $container_ips->{$name} };
    }

    return ($ipmap);
}

# create port mapping
sub _get_portmap ( $ipmap, $ports, $host_if ) {

    my $portmap = [];

    foreach my $fwd_name ( keys $ports->%* ) {

        my $port  = $ports->{$fwd_name}->{PORT};
        my $proto = $ports->{$fwd_name}->{PROTO};
        my $ipset = $ports->{$fwd_name}->{IPNAME};
        my ( $source, $sprefix ) = ();

        ( $source, $sprefix ) = split( /\//, $ports->{$fwd_name}->{SOURCE} ) if ( kexists( $ports, $fwd_name, 'SOURCE' ) );

        die 'unknown IP set' unless ( exists( $ipmap->{$ipset} ) );

        my $map = dclone( $ipmap->{$ipset} );
        $map->{port}    = $port;
        $map->{proto}   = $proto;
        $map->{source}  = $source;
        $map->{sprefix} = $sprefix;
        $map->{host_if} = $host_if;
        push $portmap->@*, $map;
    }
    return ($portmap);
}

sub _pad($string) {    # add 'silence' to string
    return join( ' ', $string, '> /dev/null 2>&1 || true' );
}

# assemble source rule if present
sub _get_source($rule) {

    return '' unless ( $rule->{source} );

    my $source = join( ' ', '-s', $rule->{source} );
    $source = join( '', $source, '/', $rule->{sprefix} ) if ( $rule->{sprefix} );    # add prefix if present

    return $source;
}

###########################################################

sub remove_fw ($container) {

    return (
        _pad("iptables -D docker_pool -j $container"),
        _pad("iptables -F $container"),
        _pad("iptables -X $container"),
        _pad("iptables -t nat -D docker_pool -j $container"),
        _pad("iptables -t nat -F $container"),
        _pad("iptables -t nat -X $container"),
    );
}

sub add_fw ($container) {

    return (
        remove_fw($container),
        _pad("iptables -N $container"),
        _pad("iptables -A docker_pool -j $container"),
        _pad("iptables -t nat -N $container"),
        _pad("iptables -t nat -A docker_pool -j $container"),
    );
}

sub add_forward_entries ( $container_name, $ips, $host_network, $ports, $external_interface ) {

    my $ipmap   = _get_ipmap( $ips, $host_network );
    my $portmap = _get_portmap( $ipmap, $ports, $external_interface );
    my @fw      = add_fw($container_name);

    return if ( scalar $portmap->@* == 0 );    # empty config

    foreach my $rule ( $portmap->@* ) {

        my $source = _get_source($rule);

        push(
            @fw,
            _pad("iptables -A $container_name -i $rule->{host_if} $source -d $rule->{container_ip} -p $rule->{proto} --dport $rule->{port} -j ACCEPT"),
            _pad(
"iptables -t nat -A $container_name -i $rule->{host_if} $source -d $rule->{host_ip} -p $rule->{proto} --dport $rule->{port} -j DNAT --to $rule->{container_ip}"
            ),
        );
    }

    return @fw;
}

