package Plugins::Config::Container::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists kdelete);
use PSI::Parse::Dir qw(get_directory_tree);
use Tree::Merge qw (override_tree add_tree);
use Tree::Slice qw(slice_tree);
use IO::Templates::Read qw(read_templates convert_meta_structure);
use IO::Templates::Parse qw(get_directory_tree_from_templates);
use IO::Templates::Meta::Parse qw(parse_meta);
use IO::Templates::Meta::Apply qw(apply_meta);
use IO::Config::Read qw(read_config load_config);
use IO::Config::Cache qw(read_cache write_cache);
use IO::Config::Check qw(check_config dir_exists);

use Plugins::Config::Container::Filter::Double qw(check_double);

our @EXPORT_OK = qw(import_hooks);

############################################################

my $IPEX         = qr/(\d{1,3}[.]\d{1,3}[.]\d{1,3}[.]\d{1,3})/x;
my $docker_paths = {
    CONFIG     => [ qr/(.+)/x, 'dircheck' ],
    DATA       => [ qr/(.+)/x, 'dircheck' ],
    PERSISTENT => [ qr/(.+)/x, 'dircheck' ],
    SHARED     => [ qr/(.+)/x, 'dircheck' ],
    MAPPED     => [ qr/(.+)/x, 'dircheck' ],
    ARCHIVE    => [ qr/(.+)/x, 'dircheck' ],
    BACKUP     => [ qr/(.+)/x, 'dircheck' ]
};
my $check = {
    NETWORK => {

        # base interface name used for container networking.
        # maximum length of interface names in linux are 15, but 2 are reserved by the container manager.
        # before introduction of 'channels', the container name was used for this
        INTERFACE => [qr/([a-z0-9]{4,13})/x],
        IP        => {                          # IPs bound to containers eth0,
            main => [qr/(\d{2,3})/x],           # main is the primary ip address of the container eth0
            '*'  => [qr/(\d{2,3})/x]            # optional secondary ip addresses, this corresponds to NETWORK_PUBLIC->ADDITIONAL
        },
        FORWARD => {                            # forward a port from the host to a container,
            '*' => {                            # the names are arbitrary
                SOURCE => [qr/($IPEX(?:\/\d{1,2})*)/x],    # optional source ip, may have optional netmask
                IPNAME => [qr/(.+)/x],                     # the container ip to use (a name from IP above)
                PROTO  => [qr/(udp|tcp)/x],                # protocol
                PORT   => [qr/(\d+)/x],                    # external port
            }
        },
    },
    DOCKER => {
        OPTS  => [qr/(.*)/x],                              # can be empty
        IMAGE => [qr/(.+)/x],
        PATHS => $docker_paths,
        MAP   => {
            '*' => {                                       # container_name
                '*' => {                                   # container_tag or 'any' for any
                    '*' => [qr/(.+)/x],                    # key: # a docker_path like PERSISTENT. value: a path inside docker_path
                }
            }
        }
    },
    START_AFTER => { '*' => [qr/(.+)/x] },
    DNS         => {

        # can be empty
        # space separated list of domain names.
        # dnsmasq will serve internal IPs for local containers
        # also, these domains get registered with the public IP of the machine in DNS
        REGISTER => [qr/(.*)/x],

        # same as REGISTER, but does not get registered in public DNS
        # dnsmasq serves local IPs for domain entries that are hosted on the same machine.
        # this is used to compose containers.
        # sometimes you just want that, and there is no need to register or the public ips might just be bogus anyway
        LOCAL => [qr/(.*)/x],

        # TXT/CAA/MX records to register in public DNS. so far they play no role outside of public DNS.
        # some services (like mail) need extra records (like DKIM, SPF)
        # structure is a domain->random->value, where:
        # - domain is the (sub)domain to put the record
        # - random is an identifier for the record (might be a name or a digit).
        #   its only use is to circumvent that arrays are not supported
        #   except for MX entries, where its used as MX priority
        # - value is the actual record
        TXT => { '*' => { '*' => [qr/(.*)/x], } },
        CAA => { '*' => { '*' => [qr/(.*)/x], } },
        MX  => { '*' => { '*' => [qr/(.*)/x], } },
    },

    CONFIG_OVERLAY      => [qr/(.+)/x],                  # despite the name, CONFIG_OVERLAY is the 'parent' config
    CONFIG              => [qr/^([.]\/.*)/x],            # and will be overridden by CONFIG contents
    OVERLAY_PERMISSIONS => $docker_paths,                # after CONFIG is loaded, CONFIG permissions will be overridden with this
                                                         # so general order is:
                                                         # CONFIG_OVERLAY(ITEM1->ITEM2->ITEM3...)->CONFIG->CONFIG_OVERLAY_PERMISSIONS
                                                         # where right overrides left.
                                                         # other (non CONFIG) entries here will be handled by genesis
                                                         # adding ROOT would be trivial, but since the permissions can only be applied
                                                         # once the entire fs tree is read, its infeasible for performance reasons.
                                                         # better use the PRE_INIT hook and use chown/mod
    PRE_INIT            => [ qr/(.+)/x, 'dircheck' ],    # optional. a path to files with cmds to run inside a container before init. no order
                                                         # files are executed line by line
    BACKUP              => {
        SCRIPT  => [qr/^([.]\/.*)/x],                    # define a script to be run prior to offsite backup transfer.
        FOLDERS => [qr/^((?:[^ ]+\s*)+)/x],              # a space separated list of names of folders to backup. corresponds to the DOCKER PATHS

    },
    SECRETS => { '*' => [qr/^(SECRETS:.+)/x], },         # the containers own secrets

    # expose configuration for other containers
    # MOVE means the file/directory is removed from the exposing container after evaluation
    # COPY means the file/directory is kept
    # SECRETS specifies a comma separated list of SECRETS entries to copy
    EXPOSE  => { '*' => { '*' => [qr/^((?:MOVE|COPY|SECRETS):.+)/x], } },
    INHERIT => { '*' => [qr/^(yes|no)/x], }                                 # the counterpart to EXPOSE, * is the first * of EXPOSE
};

sub _get_overlay_path ( $path, @root_paths ) {

    $path =~ s/^.//x;
    for my $rp (@root_paths) {
        $path =~ s/^\///;
        my $fp = join( '/', $rp, $path );
        return $fp if dir_exists $fp;
    }
    say "path: $path, root paths: ", Dumper \@root_paths;
    die "ERROR: path not found";
}

sub _read_config_from_source ( $debug, $query ) {

    #y $config_path         = $query->('CONFIG_PATH');
    my $paths   = $query->('map_container_paths');
    my $configs = {
        CONFIG_PATH         => [ $query->('CONFIG_PATH'),         load_config( read_config( $debug, $query->('CONFIG_PATH') ) ), ],
        PRIVATE_CONFIG_PATH => [ $query->('PRIVATE_CONFIG_PATH'), load_config( read_config( $debug, $query->('PRIVATE_CONFIG_PATH') ) ), ]
    };
    my @overlay_root_paths = ( $query->('CONFIG_PATH'), $query->('PRIVATE_CONFIG_PATH') );

    #my $config         = load_config( read_config( $debug, $config_path ) );
    my $templates        = {};
    my $known_ips        = {};
    my $known_interfaces = {};
    my $cache            = {};                # simple caching, to minimize re-reading of overlays
    my $tree             = {};
    my $get_templates    = sub ( $d, $p ) {

        return dclone $cache->{$p} if exists $cache->{$p};
        my $t = read_templates( $d, $p );
        $cache->{$p} = $t;
        return dclone $t;
    };
    my $get_permissions = sub ( $p ) {

        return dclone $cache->{$p} if exists $cache->{$p};
        my $t = parse_meta( $p, get_directory_tree($p) );
        $cache->{$p} = $t;
        return dclone $t;
    };

    for my $config_name ( keys $configs->%* ) {
        my $config_path = $configs->{$config_name}->[0];
        my $config      = $configs->{$config_name}->[1];

        for my $container_name ( keys $config->%* ) {

            for my $container_tag ( keys $config->{$container_name}->%* ) {

                my $container         = $config->{$container_name}->{$container_tag};
                my $container_nametag = join( '_', $container_name, $container_tag );

                check_config(
                    $debug,
                    {
                        name       => $container_nametag,
                        config     => $container,
                        definition => $check
                    }
                );
                check_double( $known_ips, $container_nametag, $container->{NETWORK}->{IP} );
                $config->{$container_name}->{$container_tag}->{NAME} = $container_nametag;

                my $if_name = $container->{NETWORK}->{INTERFACE};
                $known_interfaces->{$if_name} = $container_nametag unless ( exists( $known_interfaces->{$if_name} ) );
                die "ERROR: interface_name $if_name already in use by $known_interfaces->{$if_name}" if ( $known_interfaces->{$if_name} ne $container_nametag );

                # add host paths
                my $host_paths = $query->("map_host_paths $container_name $container_tag");
                for my $k ( keys $host_paths->%* ) {
                    $container->{DOCKER}->{PATHS}->{$k} = $host_paths->{$k} unless exists( $container->{DOCKER}->{PATHS}->{$k} );
                }
                $container->{CONTAINER}->{PATHS} = $paths;    # add container paths

                # container config belongs to docker datastruct.
                my $container_path = delete( $container->{CONFIG} );

                if ( exists( $container->{BACKUP} ) ) {

                    my $script_path = kdelete( $container, 'BACKUP', 'SCRIPT' );
                    if ($script_path) {

                        $script_path =~ s/^.//x;
                        $script_path = join( '', $config_path, $script_path );
                        $templates->{$container_name}->{$container_tag}->{backup} = read_templates( $debug, $script_path );
                    }

                    my $folders = kdelete( $container, 'BACKUP', 'FOLDERS' );
                    if ($folders) {
                        $container->{BACKUP}->{FOLDERS} = [];
                        for my $folder ( split( /\s+/, $folders ) ) {

                            die "ERROR: $folder not found in docker path definitions" unless exists( $container->{DOCKER}->{PATHS}->{$folder} );
                            push $container->{BACKUP}->{FOLDERS}->@*, $container->{DOCKER}->{PATHS}->{$folder};

                        }
                    }
                }

                # now load overlays and join them with container config
                if ( exists( $container->{CONFIG_OVERLAY} ) ) {

                    my $overlay = delete $container->{CONFIG_OVERLAY};
                    $templates->{$container_name}->{$container_tag} = {} unless exists( $templates->{$container_name}->{$container_tag} );
                    for my $layer ( split( /\s+/x, $overlay ) ) {

                        if ( $layer =~ s/^[.]//x ) {    # might be an absolute path
                            $layer = _get_overlay_path( $layer, @overlay_root_paths );
                        }

                        #say $layer;
                        override_tree( $templates->{$container_name}->{$container_tag}, $get_templates->( $debug, $layer ) );
                    }

                    override_tree( $templates->{$container_name}->{$container_tag},
                        $get_templates->( $debug, _get_overlay_path( $container_path, @overlay_root_paths ) ) );
                }
                else {
                    $templates->{$container_name}->{$container_tag} = $get_templates->( $debug, $container_path );
                }

                # load permission overlays
                if ( exists( $container->{OVERLAY_PERMISSIONS} ) ) {

                    my $l = $container->{OVERLAY_PERMISSIONS};
                    for my $overlay ( keys $l->%* ) {

                        my $overlay_path = $l->{$overlay};

                        if ( $overlay_path =~ s/^[.]//x ) {    # might be an absolute path
                            $overlay_path = join( '', $config_path, $overlay_path );
                        }
                        $l->{$overlay} = $get_permissions->($overlay_path);
                    }
                }

                # load pre init files
                if ( exists( $container->{PRE_INIT} ) ) {

                    my $path = $container->{PRE_INIT};
                    if ( $path =~ s/^[.]//x ) {                # might be an absolute path
                        $path = _get_overlay_path( $path, @overlay_root_paths );
                    }
                    $container->{PRE_INIT} = read_templates( $debug, $path );
                }

                # update config overlay permissions now, others are applied at runtime
                if ( kexists( $container, 'OVERLAY_PERMISSIONS', 'CONFIG' ) ) {
                    my $permission_overlay = delete $container->{OVERLAY_PERMISSIONS}->{CONFIG};
                    my $meta_tree = apply_meta( get_directory_tree_from_templates( $templates->{$container_name}->{$container_tag} ), $permission_overlay );
                    override_tree( $templates->{$container_name}->{$container_tag}, convert_meta_structure($meta_tree) );
                }

                # check maps. this is not a complete check. the rest is done during build,
                # when we know what containers are actually on a machine
                # sadly, now that container config is read from multiple locations, this check would only work for containers in the same location.
                # therefor deactivated
                #if ( kexists( $container, 'DOCKER', 'MAP' ) ) {
                #    my $cond = sub ($b) {
                #        return 1 unless ref $b->[0];
                #        return 0;
                #    };
                #    for my $e ( slice_tree( $container->{DOCKER}->{MAP}, $cond ) ) {
                #        my ( $cn, $real_ct, $cv, $p ) = $e->[1]->@*;
                #        my ($ct) = ( keys $config->{$cn}->%* ) if ( $real_ct eq 'any' );    # if any, use a random one to check
                #        die "ERROR: MAP container '$cn' does not exists (in $container_nametag)" unless exists $config->{$cn};
                #        die "ERROR: MAP container tag '$ct' does not exist (in $container_nametag -> $cn:$real_ct)" unless exists $config->{$cn}->{$ct};
                #    }
                #}
            }
        }
        add_tree $tree, $config;
    }
    return ( $tree, $templates );
}

sub import_loader ( $debug, $query ) {

    my $cache_path      = $query->('CACHE');
    my $cache_config    = 'config.cfgen';
    my $cache_templates = 'templates.cfgen';
    my ( $config, $templates ) = read_cache( $debug, $cache_path, $cache_config, $cache_templates );

    if ( !$config || !$templates ) {
        ( $config, $templates ) = _read_config_from_source( $debug, $query );
        write_cache(
            $debug,
            $cache_path,
            {
                $cache_config    => $config,
                $cache_templates => $templates
            }
        );
    }

    return {
        state => {
            container => sub () {
                return dclone {
                    config    => $config,
                    templates => $templates,
                };
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Container',
        require => ['Paths'],
        loader  => \&import_loader,
        data    => {
            CONFIG_PATH         => 'CONFIG_PATH',
            PRIVATE_CONFIG_PATH => 'PRIVATE_CONFIG_PATH',
            CACHE               => 'CACHE',
            paths               => 'state paths container',
            map_host_paths      => 'state map_container_host_paths',
            map_container_paths => 'state map_container_paths',
        }
    };
}

