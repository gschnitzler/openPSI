package Plugins::Config::Cluster::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);
use Net::Netmask;

use InVivo qw(kexists);
use Tree::Merge qw(add_tree);
use Tree::Slice qw(slice_tree);

use IO::Config::Cache qw(read_cache write_cache);
use IO::Config::Check qw(check_config);
use IO::Config::Read qw(read_config_single load_config);

use Plugins::Config::Cluster::Config::Services qw(service_definitions);

our @EXPORT_OK = qw(import_hooks);

###########################################

my $IPEX = qr/^(\d{1,3}[.]\d{1,3}[.]\d{1,3}[.]\d{1,3})/x;

my $adjacent_check = {    # ADJACENT might empty
    '*' => {
        '*' => {
            SSH => {
                PRIV => [qr/^(.+)/x],
                KEY  => [qr/^(\/.*)/x]
            },
            USEHOSTKEY => [qr/^([01]{1})/x],
        }
    }
};

my $component_check = {

    CONTAINER => {
        '*' => {    # container name
            '*' => {    # container tag
                ENABLE  => [qr/^\s*(yes|no)/x],
                OPTIONS => {
                    '*' => [qr/^(.+)/x],    # useful for cluster wide configurations that would otherwise require duplicating containers.
                                            # this way, config can be injected without requiring unique ids. mariadbs galera config is an example.
                                            # be sure to validate the keys somewhere
                },
            },
        }
    },
    ROLES   => { '*' => [qr/^\s*(yes|no)/x] },
    SERVICE => service_definitions(),

};

# the idea here is:
# on a developer machine, say toms, all the containers are tagged with DEVTOMx
# so, when he stages DEVTOM2, data gets pushed to STAGETOM2, so its pushed there
# from there its staged to STAGING, which then can be staged to PRODUCTION
# this would also work in rings, say DEVTOM on devtom stages to STAGETOM on stagecontrol,
# which stages to TESTTOM1 in the staging cluster, which stages to STAGING on stagecontrol,
# which stages to PRODUCTION on de-cluster1
my $stage_check = { '*' => [qr/^(.+)/x] };

my $check_machine_network = {

    # although the section names are not checked, hardcoded names are used everywhere else (plugins, config, templates, scripts)
    # INTERN is used for docker/containers
    # PUBLIC is the main interface.
    # PRIVATE is a NATed network
    # these names are hardcoded, there is no point in automation.
    '*' => {

        # notice that DHCP only affects the distributions network configuration file.
        # all the other entries (like ADDRESS) are still required.
        # otherwise, all interfaces would have to be accessed via state variables (because of dhcp).
        # however, all the installed configuration files (hostos, containers) are static after generation
        # thus, a lease change would require a regeneration of all configfiles and a restart, or the system would enter undefined state.
        # genesis is explicitly designed to not work that way.
        DHCP        => [qr/^\s*(yes|no)/x],
        ADDRESS     => [$IPEX],
        NETMASK     => [qr/^(\d{2})/x],
        BROADCAST   => [$IPEX],
        ROUTER      => [$IPEX],
        INTERFACE   => [qr/^([a-z0-9]+)/x],
        EXTRA_ROUTE => [qr/^(.+)/x],          # additional routes. thanks hetzner. you really helped me out at 2am when all servers where down

        # additional ips bound to INTERFACE
        # every port bound in container FORWARD is tied to a host ip <> container ip pair
        # pairs are defined by names. (think of '*' as a placeholder name)
        ADDITIONAL => {
            '*' => {
                ADDRESS   => [$IPEX],
                NETMASK   => [qr/^(\d{2})/x],
                BROADCAST => [$IPEX],
                ROUTER    => [$IPEX],
                INTERFACE => [qr/^([a-z0-9]+)/x],
            }
        }
    }
};

my $check_cluster = {
    COMPONENTS  => { $component_check->%* },
    ADJACENT    => { $adjacent_check->%* },
    CLUSTER_GID => [qr/^([0-9]{4})/x],

    # stages may not be overridden by machines
    STAGE => { $stage_check->%* },
};

my $check_machine = {
    RAID => {

        # template toolkit does not allow '0' as a value. (it gets replaced by '')
        # i had so many headaches with TT, maybe its time to switch to something else
        # anyway, as a quickfix, raidmodes are now defined as strings. possible are:
        # raid0, raid1, raidS (single disk)
        LEVEL => [qr/^(raid[01S]{1})/x],

        # with the advent of NVMe, the disks need to be part of the machine config,
        # (global sda/b does not hold true anymore)
        DISK1 => [qr/^(\/dev\/.+)/x],
        DISK2 => [qr/^(\/dev\/.+)/x],
    },
    NAMES => {
        FULL  => [qr/^([a-zA-Z0-9.-]+)/x],
        SHORT => [qr/^([a-zA-Z0-9.-_]+)/x],

        # accountname to use when connection to other machines
        MRO => [qr/^([a-zA-Z0-9-_]+)/x],
    },
    GROUP    => [qr/^([a-zA-Z0-9.-_]+)/x],
    HOST_UID => [qr/^([0-9]{4})/x],
    NETWORK  => { $check_machine_network->%* },
    DNS      => {
        NAMESERVER1 => [$IPEX],
        NAMESERVER2 => [$IPEX],
        NAMESERVER3 => [$IPEX],
        DOMAIN      => [qr/^([a-z0-9.-]+)/x]
    },

    # overrides group settings
    COMPONENTS => { $component_check->%* },
    ADJACENT   => { $adjacent_check->%* },
};
###################################################

sub _find_double_ips ( $name, $knownips, $networks ) {

    my $cond = sub ($branch) {
        my $bt = $branch->[0];
        return unless ( ref $bt eq 'HASH' );
        return 1 if ( exists( $bt->{ADDRESS} ) && exists( $bt->{NETMASK} ) && exists( $bt->{INTERFACE} ) );
        return;
    };

    my @match = slice_tree( $networks, $cond );
    die "ERROR: no ADDRESS found in $name" if ( scalar @match == 0 );

    foreach my $entry (@match) {

        my $ip = $entry->[0]->{ADDRESS};

        die "ERROR: IP $ip is already used by $knownips->{$ip}" if ( exists( $knownips->{$ip} ) );
        $knownips->{$ip} = $name;
    }
    return;
}

sub _find_double_guids ( $tree ) {

    my $known = {};
    my $cond  = sub ($branch) {
        my $bt = $branch->[0];
        return unless ( ref $bt eq 'HASH' );
        return 1 if ( exists( $bt->{CLUSTER_GUID} ) && exists( $bt->{HOST_UID} ) );
        return;
    };

    foreach my $entry ( slice_tree( $tree, $cond ) ) {

        my $uid   = $entry->[0]->{HOST_UID};
        my $gid   = $entry->[0]->{CLUSTER_GUID};
        my $name  = $entry->[0]->{NAMES}->{SHORT};
        my $group = $entry->[0]->{GROUP};

        die "ERROR: UID $uid of $name is already used by $known->{UID}->{$uid}" if ( kexists( $known, 'UID', $uid ) );
        die "ERROR: GID $gid of $group is already used by $known->{GID}->{$gid}" if ( kexists( $known, 'GID', $gid ) && $known->{GID}->{$gid} ne $group );
        $known->{UID}->{$uid} = $name;
        $known->{GID}->{$gid} = $group;
    }
    return;
}

sub _expand_ipsec_ips ( $network, $ipsec ) {

    if ( exists( $ipsec->{ENABLE} ) && $ipsec->{ENABLE} eq 'yes' ) {

        my $interface_name = $ipsec->{INTERFACE};

        die "ERROR: IPSEC pool termination interface $interface_name not found in interface definitions"
          unless exists $network->{$interface_name};

        $ipsec->{INTERFACE} = $network->{$interface_name}->{INTERFACE};
    }
    return;
}

sub _expand_network ($network_cfg) {

    foreach my $network_name ( keys( $network_cfg->%* ) ) {

        my $network = $network_cfg->{$network_name};

        # dont add NETWORK if the interface is set to DHCP
        next if ( exists( $network->{DHCP} ) && $network->{DHCP} eq 'yes' );

        # die if insufficient information presdent
        die 'ERROR: interface does not have ADDRESS or NETMASK' if ( !exists( $network->{ADDRESS} ) || !exists( $network->{NETMASK} ) );

        # 'new' belongs to Net::Netmask. critic complains and is probably right, but its straight out of Net::Netmasks docs
        my $block = new Net::Netmask( join( '/', $network->{ADDRESS}, $network->{NETMASK} ) );    ## no critic
        $network->{NETWORK} = join( '/', $block->base(), $network->{NETMASK} );
    }

    return;
}

sub _expand_dhcp_ips ( $networks, $dhcp ) {

    return if ( !exists( $dhcp->{ENABLE} ) || $dhcp->{ENABLE} ne 'yes' );

    my $ifname = $dhcp->{INTERFACE};
    my $start  = $dhcp->{START};
    my $end    = $dhcp->{END};
    my $hosts  = $dhcp->{HOSTS};

    my $router = $networks->{$ifname}->{ADDRESS};
    $ifname = $networks->{$ifname}->{INTERFACE};
    die "ERROR: interface $ifname not found in NETWORK definition" unless ($ifname);

    my $net = $router;
    $net =~ s/(.*)[.]\d+$/$1./x;

    $dhcp->{INTERFACE} = $ifname;
    $dhcp->{START}     = join( '', $net, $start );
    $dhcp->{END}       = join( '', $net, $end );
    $dhcp->{ROUTER}    = $router;

    foreach my $host ( keys $hosts->%* ) {

        $hosts->{$host}->{IP} = join( '', $net, $hosts->{$host}->{IP} );

        foreach my $nat_name ( keys $hosts->{$host}->{NAT}->%* ) {

            my $nat           = $hosts->{$host}->{NAT}->{$nat_name};
            my $nat_interface = $nat->{SOURCE_INTERFACE};

            $nat_interface = $networks->{$nat_interface}->{INTERFACE};
            die "ERROR: interface $nat_interface not found in NETWORK definition" unless ($nat_interface);
            $nat->{SOURCE_INTERFACE} = $nat_interface;
        }
    }
    return;
}

sub _load_machines ( $debug, $path, $cluster_config ) {

    my $machines = load_config( read_config_single( $debug, $path ) );

    die "ERROR: no machines found in $path" unless ($machines);
    my $knownips     = {};
    my $machine_list = {};

    # say Dumper $machines;
    foreach my $machine_name ( keys $machines->%* ) {

        my $machine = $machines->{$machine_name};
        my $group   = $machine->{GROUP};

        check_config(
            $debug,
            {
                name       => "$group/$machine_name",
                config     => $machine,
                definition => $check_machine
            }
        );

        _find_double_ips( "$group/$machine_name", $knownips, $machine->{NETWORK} );

        # add a COPY of the original cluster configuration to the machine, otherwise a data manipulation would alter the original
        # (as happens with _expand_ipsec)
        add_tree( $machine, dclone $cluster_config );
        _expand_ipsec_ips( $machine->{NETWORK}, $machine->{COMPONENTS}->{SERVICE}->{strongswan} );
        _expand_dhcp_ips( $machine->{NETWORK}, $machine->{COMPONENTS}->{SERVICE}->{dhcp} );
        _expand_network( $machine->{NETWORK} );
        $machine_list->{$machine_name} = $machine;
    }

    #   say Dumper $machine_config;
    return $machine_list;
}

sub _read_config_from_source ( $debug, $query ) {
    my $config_path       = $query->('CONFIG_PATH');
    my $cluster           = load_config( read_config_single( $debug, $config_path ) );
    my $assembled_cluster = {};

    foreach my $cluster_name ( keys $cluster->%* ) {

        my $machine_path = join( '/', $config_path, $cluster_name );

        #   say Dumper $cluster_name, $cluster->{$cluster_name}, $check_cluster;
        my $cluster_config = check_config(
            $debug,
            {
                name       => $cluster_name,
                config     => $cluster->{$cluster_name},
                definition => $check_cluster
            }
        );
        $assembled_cluster->{$cluster_name} = _load_machines( $debug, $machine_path, $cluster_config );
    }

    _find_double_guids($assembled_cluster);
    return $assembled_cluster;
}

sub import_loader ( $debug, $query ) {

    my $cache_path    = $query->('CACHE');
    my $cache_cluster = 'cluster.cfgen';
    my $cluster       = read_cache( $debug, $cache_path, $cache_cluster );

    if ( !$cluster ) {
        $cluster = _read_config_from_source( $debug, $query );
        write_cache(
            $debug,
            $cache_path,
            {
                $cache_cluster => $cluster,
            }
        );
    }

    return {
        state => {
            cluster => sub () {
                return dclone $cluster;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Cluster',
        require => [],
        loader  => \&import_loader,
        data    => {
            CONFIG_PATH => 'CONFIG_PATH',
            CACHE       => 'CACHE'
        }
    };
}

