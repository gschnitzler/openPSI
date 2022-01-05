package Plugins::Network::System::GetIP;

use ModernStyle;
use Exporter qw(import);
use Storable qw(dclone);
use Data::Dumper;

use Tree::Slice qw(slice_tree);
use PSI::RunCmds qw(run_open);
use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw(get_ip check_ip);

###################################################
my $IPEX = qr/(\d{1,3}[.]\d{1,3}[.]\d{1,3}[.]\d{1,3})/x;
###################################################

sub _get_routes () {
    return run_open 'ip route';
}

sub _get_devinfo($interface) {
    return run_open "ip addr show $interface 2>&1";
}

sub _get_route_info($interface) {
    return run_open "ip route show dev $interface 2>&1";
}

sub _get_ips () {

    my $ips = {};
    foreach my $route ( _get_routes() ) {

        $ips->{$2} = $3
          if (
            $route =~ m{
            ^
            $IPEX/\d+
            \s+
            dev
            \s+
            ([^\s]+)    # device
            \s+
            .*
            src
            \s+
            $IPEX       # address
            \s*
            .*
            $
            }x
          );
    }
    return $ips;
}

sub check_ip ($networks) {

    my $ips        = _get_ips();
    my $matched_ip = '';

    foreach my $dev ( keys $ips->%* ) {

        my $addr = $ips->{$dev};
        my $cond = sub ($branch) {
            my $bt = $branch->[0];
            return unless ( ref $bt eq 'HASH' );
            return 1 if ( exists( $bt->{ADDRESS} ) && $bt->{ADDRESS} eq $addr && exists( $bt->{INTERFACE} ) && $bt->{INTERFACE} eq $dev );
            return;
        };

        my @match = slice_tree( $networks, $cond );

        if ( scalar @match ) {
            $matched_ip = $match[0]->[1];
            last;
        }
    }

    return if ( exists( $ENV{GENESIS_TEST} ) && $ENV{GENESIS_TEST} eq '1' );    # this is for testing in cfgen.
    die 'ERROR: IP configuration does not match' unless $matched_ip;
    return;
}

sub _update_dhcp_config ($network) {

    my $interface = $network->{INTERFACE};

    return unless dir_exists "/proc/sys/net/ipv4/conf/$interface";              # ip cmd will die when $interface does not exist
    return if ( !exists( $network->{DHCP} ) || $network->{DHCP} ne 'yes' );

    foreach my $line ( _get_devinfo($interface) ) {

        next if ( $line =~ m/inet6/x );                                         # ignore ipv6
        next if ( $line =~ m/secondary/x );                                     # ignore ADDITIONAL ips... such setups are not supported by dhcp

        if (
            $line =~ m{
                \s+
                inet
                \s+
                $IPEX
                /(\d+)
                \s+
                brd
                \s+
                $IPEX
                \s+
                .*
                }x
          )
        {
            my ( $address, $netmask, $broadcast ) = ( $1, $2, $3 );
            $network->{NETMASK}   = $netmask;
            $network->{BROADCAST} = $broadcast;
            $network->{ADDRESS}   = $address;
        }
    }

    foreach my $line ( _get_route_info($interface) ) {

        if ( $line =~ m{^default\s+via\s+$IPEX\s+}x ) {
            $network->{ROUTER} = $1;
            next;
        }

        $network->{NETWORK} = "$1/$2" if ( $line =~ m{^$IPEX/(\d+)}x );
    }
    return;
}

sub get_ip ( $networks, @arguments ) {

    my $immutable_networks = dclone($networks);

    # fill in dhcp configuration
    foreach my $network_name ( keys $immutable_networks->%* ) {
        my $network = $immutable_networks->{$network_name};
        _update_dhcp_config($network);    # always override wanted config with real config
    }

    my $ref = $immutable_networks;
    foreach my $arg (@arguments) {

        die "ERROR: data not found: @arguments" unless exists( $ref->{$arg} );
        $ref = $ref->{$arg};
    }

    return $ref;
}
1;
