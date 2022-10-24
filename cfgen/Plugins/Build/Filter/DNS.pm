package Plugins::Build::Filter::DNS;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use Tree::Merge qw(add_tree);

our @EXPORT_OK = qw(generate_dns);

####################################

# get all dns entries from config
sub _filter_config($config) {

    my @machines = ();

    for my $c ( keys $config->%* ) {

        for my $m ( keys $config->{$c}->%* ) {

            my $machine_self               = $config->{$c}->{$m}->{machine}->{self};
            my $machine_domain             = $machine_self->{NAMES}->{FULL};
            my $machine_network            = $machine_self->{NETWORK}->{PUBLIC};
            my $machine_ips->{IPS}->{main} = '';
            $machine_ips->{MACHINE} = $machine_domain;

            # IGNORE is used by the diff module to ignore this entry.
            # so the entry is neither added nor deleted in DNS.
            if ( ( kexists( $machine_self, 'NETWORK', 'PUBLIC', 'DHCP' ) && $machine_self->{NETWORK}->{PUBLIC}->{DHCP} eq 'yes' )
                || $machine_self->{NETWORK}->{PUBLIC}->{ADDRESS} =~ /^192\.168\./ )
            {
                $machine_ips->{IPS}->{main} = 'IGNORE';
            }
            else {

                $machine_ips->{IPS}->{main} = $machine_network->{ADDRESS};

                if ( exists $machine_network->{ADDITIONAL} ) {

                    for my $ma ( keys $machine_network->{ADDITIONAL}->%* ) {
                        $machine_ips->{IPS}->{$ma} = $machine_network->{ADDITIONAL}->{$ma}->{ADDRESS};
                    }
                }
            }

            push @machines, [ $machine_ips, _filter_container( $config->{$c}->{$m}->{container} ) ];
        }
    }
    return @machines;
}

sub _add_register ( $t, $dns, $ip_names ) {

    return unless ( exists $dns->{REGISTER} );

    my @container_dns = split( /\s+/, $dns->{REGISTER} );

    # ignore entries that dont register dns entries
    return unless scalar @container_dns;

    for my $ip_name ( keys $ip_names->%* ) {
        push $t->{$ip_name}->@*, @container_dns;
    }
    return;
}

sub _filter_container($containers) {

    my $container = {
        A   => {},
        TXT => {},
        MX  => {},
        CAA => {},
    };

    for my $c ( keys $containers->%* ) {
        for my $s ( keys $containers->{$c}->%* ) {

            my $machine_container = $containers->{$c}->{$s}->{config};

            _add_register( $container->{A}, $machine_container->{DNS}, $machine_container->{NETWORK}->{IP} );

            for my $type ( 'TXT', 'CAA', 'MX' ) {
                add_tree $container, { $type => $machine_container->{DNS}->{$type} } if exists $machine_container->{DNS}->{$type};
            }
        }
    }
    return $container;
}

sub _get_root_domain($domain) {

    my @subdomains = split( /[.]/, $domain );

    die 'ERROR: root domain to short' if scalar @subdomains < 1;

    # when the array only has 2 entries (root.tld), do nothing
    if ( scalar @subdomains > 1 ) {

        # check if the domain has known sub tlds
        # this should better be handled via a configfile.
        # until it is, be sure to also update the GetWildcards code in dnssl
        if ( $subdomains[-2] eq 'co' && $subdomains[-1] eq 'uk' ) {
            @subdomains = ( $subdomains[-3], $subdomains[-2], $subdomains[-1] );
        }
        elsif ( $subdomains[-2] eq 'com' && $subdomains[-1] eq 'au' ) {
            @subdomains = ( $subdomains[-3], $subdomains[-2], $subdomains[-1] );
        }
        else {
            @subdomains = ( $subdomains[-2], $subdomains[-1] );
        }

    }

    my $root_domain = join( '.', @subdomains );
    die "ERROR: $domain is not a valid domain" unless $root_domain;
    return $root_domain;

}

sub _get_records ( $type, $t ) {

    my $tree = {};
    for my $domain ( keys $t->%* ) {

        my $zone = _get_root_domain($domain);

        for my $key ( keys $t->{$domain}->%* ) {

            my $v = $t->{$domain}->{$key};

            $tree->{$zone}->{$type}->{$domain}->{$v} = {
                type      => $type,
                proxied   => 0,
                content   => $v,
                name      => $domain,
                zone_name => $zone,
                id        => 'psi-config',
                zone_id   => 'psi-config',
            };
            $tree->{$zone}->{$type}->{$domain}->{$v}->{priority} = $key if $type eq 'MX';
        }
    }
    return $tree;
}
####################################

sub generate_dns ( $config ) {

    print_table( 'Generate DNS config (not yet saved)', '', ': ' );

    my $tree = {};

    foreach my $e ( _filter_config($config) ) {

        my $machine           = $e->[0];
        my $machine_container = $e->[1];
        my $machine_name      = $machine->{MACHINE};
        my $machine_ip        = $machine->{IPS}->{main};

        ########## TXT/CAA/MX records
        for my $type ( 'TXT', 'CAA', 'MX' ) {
            add_tree $tree, _get_records( $type, $machine_container->{$type} ) if exists $machine_container->{$type};
        }

        ########## A records

        ## records for machine names
        my $mc_a = $machine_container->{A};
        my $zone = _get_root_domain($machine_name);

        $tree->{$zone}->{A}->{$machine_name}->{$machine_ip} = {
            type      => 'A',
            proxied   => 0,
            content   => $machine_ip,
            name      => $machine_name,
            zone_name => $zone,
            id        => 'psi-config',
            zone_id   => 'psi-config',
        };

        ## records for containers
        for my $ip_name ( keys $machine->{IPS}->%* ) {

            next unless exists( $mc_a->{$ip_name} );
            my $container_ip = $machine->{IPS}->{$ip_name};

            foreach my $container_dns_name ( $mc_a->{$ip_name}->@* ) {

                my $container_zone = _get_root_domain($container_dns_name);

                $tree->{$container_zone}->{A}->{$container_dns_name}->{$container_ip} = {
                    type      => 'A',
                    proxied   => 0,
                    content   => $container_ip,
                    name      => $container_dns_name,
                    zone_name => $container_zone,
                    id        => 'psi-config',
                    zone_id   => 'psi-config',

                };

                # could be that a container is enabled on prod and a dev machine. remove IGNORE entries when a real IP is also present
                if ( exists $tree->{$container_zone}->{A}->{$container_dns_name}->{IGNORE} && $container_ip ne 'IGNORE' ) {
                    delete $tree->{$container_zone}->{A}->{$container_dns_name}->{IGNORE};
                }
            }
        }
    }

    say 'OK';
    return dclone $tree;
}
