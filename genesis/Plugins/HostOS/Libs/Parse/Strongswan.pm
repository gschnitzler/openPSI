package Plugins::HostOS::Libs::Parse::Strongswan;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use Tree::Slice qw(slice_tree);
use IO::Templates::Parse qw(check_and_fill_template check_and_fill_template_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(gen_strongswan);

#####################################################################

sub _get_network ( $interface, $config ) {

    my $cond = sub ($branch) {
        my $bt = $branch->[0];
        return unless ( ref $bt eq 'HASH' );
        return 1 if ( exists( $bt->{INTERFACE} ) && $bt->{INTERFACE} eq $interface );
        return;
    };

    my @match = slice_tree( $config, $cond );
    die "ERROR: network config for interface $interface not found" unless scalar @match;

    return $match[0]->[0];
}

sub _gen_ipsec_conf ( $p ) {

    my $name          = $p->{name};
    my $nodes         = $p->{nodes};
    my $roadwarriors  = $p->{roadwarriors};
    my $substitutions = $p->{substitutions};
    my $config        = $p->{config};
    my $template      = $p->{templates};
    my @content       = ();

    push( @content, check_and_fill_template( $template->{global}->{CONTENT}, $substitutions ) );

    my $host_network = _get_network( $config->{INTERFACE}, $substitutions->{state}->{network} );

    foreach my $key ( keys $nodes->%* ) {

        my $node = $nodes->{$key};

        next if ( !kexists( $node, 'COMPONENTS', 'SERVICE', 'strongswan', 'ENABLE' ) || $node->{COMPONENTS}->{SERVICE}->{strongswan}->{ENABLE} ne 'yes' );
        my $node_name = $node->{NAMES}->{SHORT};
        $node->{left_cert} = "$name.pem";
        push @content, ["conn $name-$node_name"];

        # in the template, we cant simply substitute the interface config, so map here
        $node->{left_network}  = $host_network;
        $node->{right_network} = _get_network( $node->{COMPONENTS}->{SERVICE}->{strongswan}->{INTERFACE}, $node->{NETWORK} );

        push @content, check_and_fill_template( $template->{node}->{CONTENT}, { $substitutions->%*, plugin => { node => $node } } );
    }

    foreach my $key ( keys $roadwarriors->%* ) {

        my $roadwarrior = $roadwarriors->{$key};

        next unless exists( $roadwarrior->{VPN} );

        #        my $rw_name = $roadwarrior->{NAME};
        #        push @content, ["conn $rw_name"];
        push @content, ['conn roadwarrior'];
        push(
            @content,
            check_and_fill_template(
                $template->{roadwarrior}->{CONTENT},
                {
                    $substitutions->%*,
                    plugin => {
                        node => {

                            left_network => $host_network,
                            left_cert    => "$name.pem"
                        }
                    }
                }
            )
        );

        # a single entry is enough
        last;
    }

    my $cf = {
        LOCATION => $template->{global}->{LOCATION},
        CHMOD    => $template->{global}->{CHMOD},
    };

    foreach (@content) {
        push $cf->{CONTENT}->@*, $_->@*;
    }
    return $cf;
}

sub _gen_ipsec_secrets ( $template, $name, $ipsec ) {

    my $ipsec_secrets = {
        LOCATION => $template->{LOCATION},
        CHMOD    => $template->{CHMOD},
        CONTENT  => [": RSA $name.pem"]
    };

    my $ipsec_private_key = {
        LOCATION => "/etc/ipsec.d/private/$name.pem",
        CHMOD    => '600',
        CONTENT  => [ $ipsec->{PRIV} ]
    };

    my $ipsec_cert = {
        LOCATION => "/etc/ipsec.d/certs/$name.pem",
        CHMOD    => '600',
        CONTENT  => [ $ipsec->{CERT} ]
    };

    my $ipsec_ca_cert = {
        LOCATION => '/etc/ipsec.d/cacerts/ca.pem',
        CHMOD    => '600',
        CONTENT  => [ $ipsec->{CA} ]
    };

    return $ipsec_secrets, $ipsec_private_key, $ipsec_cert, $ipsec_ca_cert;
}

sub _gen_charon_conf ( $template, $substitutions ) {

    return {
        LOCATION => $template->{LOCATION},
        CHMOD    => $template->{CHMOD},
        CONTENT  => check_and_fill_template( $template->{CONTENT}, $substitutions )
    };
}

sub _gen_dhcp_conf ( $template, $interface, $substitutions ) {

    my $network = _get_network( $interface, $substitutions->{state}->{network} );

    return {
        LOCATION => $template->{LOCATION},
        CHMOD    => $template->{CHMOD},
        CONTENT  => check_and_fill_template( $template->{CONTENT}, { $substitutions->%*, plugin => { node => { dhcp => $network->{ADDRESS} } } } )
    };
}

sub _gen_updown ( $template ) {

    my @content = ();

    # shortcut for unified s2s template
    return {
        LOCATION => join( '', $template->{LOCATION}, 's2s' ),
        CHMOD    => $template->{CHMOD},
        CONTENT  => $template->{CONTENT}
    };

    # foreach my $key ( keys $nodes->%* ) {

    #     my $node      = $nodes->{$key};
    #     my $node_name = $node->{NAMES}->{SHORT};

    #     push @content,
    #         {
    #         LOCATION => join( '', $template->{LOCATION}, $node_name ),
    #         CHMOD    => $template->{CHMOD},
    #         CONTENT => check_and_fill_template( $template->{CONTENT}, { node => $node } )
    #         };
    # }

    # foreach my $key ( keys $roadwarriors->%* ) {

    #     my $roadwarrior = $roadwarriors->{$key};

    #     next unless exists( $roadwarrior->{VPN} );

    #     my $rw_name = $roadwarrior->{NAME};

    #     # unimplemented
    # }

    # return @content;

}

##### frontend

sub gen_strongswan ($query) {

    print_table 'Generating strongswan Config:', ' ', ': ';
    my $templates      = $query->('templates strongswan');
    my $substitutions  = $query->('substitutions strongswan');
    my $scripts        = $query->('scripts strongswan');
    my $nodes          = $query->('config strongswan nodes');
    my $roadwarriors   = $query->('config strongswan roadwarriors');
    my $ipsec          = $query->('config strongswan config');
    my $name           = $query->('config strongswan name');
    my @cf             = ();
    my $filled_scripts = check_and_fill_template_tree( $scripts, $substitutions );

    push @cf, _gen_ipsec_secrets( $templates->{'ipsec.secrets'}, $name, $ipsec, );
    push @cf, _gen_charon_conf( $templates->{'charon.conf'}, $substitutions );
    push @cf, _gen_dhcp_conf( $templates->{'dhcp.conf'}, $ipsec->{INTERFACE}, $substitutions );
    push @cf, _gen_updown( $templates->{'updown_s2s'} );

    # this modifies the variables. let this be the last action
    push @cf,
      _gen_ipsec_conf(
        {
            name          => $name,
            nodes         => $nodes,
            roadwarriors  => $roadwarriors,
            substitutions => $substitutions,
            config        => $ipsec,
            templates     => {
                global      => $templates->{'ipsec.conf_global'},
                node        => $templates->{'ipsec.conf_node'},
                roadwarrior => $templates->{'ipsec.conf_roadwarrior'},
            }
        }
      );

    say 'OK';

    return $filled_scripts, @cf;
}

1;
