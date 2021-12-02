package Plugins::Deploy::Cmds::Push;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Tag qw(get_tag);
use PSI::Console qw(print_table);
use PSI::Store qw(store_image);

use Plugins::Deploy::Libs::Machines qw(list_machines);
use Plugins::Deploy::Libs::Container qw(get_container);
use Plugins::Deploy::Libs::Image qw(make_image);
use Plugins::Deploy::Libs::SSH qw(scp_deploy);

our @EXPORT_OK = qw(import_push);

#############

sub _add_paths ( $machines, $container_cfg, $p ) {

    my $images = $p->{images};
    my $wanted = $p->{wanted};

    # images consist of 2 parts: image and imagename
    my ( $wanted_prefix, $wanted_type ) = split /_/, $wanted;

    my $image_sub = sub () {
        if ( kexists( $images, $wanted_prefix, $wanted_type, 'latest' ) ) {

            foreach my $machine ( keys $machines->%* ) {
                $machines->{$machine}->{source} = $images->{$wanted_prefix}->{$wanted_type}->{latest};
                $machines->{$machine}->{target} = $p->{image_path};
            }
        }
        return $machines;
    };

    my $container_data_sub = sub() {
        if ( exists( $p->{container} ) && exists( $p->{tag} ) && kexists( $container_cfg, $p->{container}, $p->{tag}, 'config' ) ) {

            my $datestring    = get_tag;
            my $source_folder = $container_cfg->{ $p->{container} }->{ $p->{tag} }->{config}->{DOCKER}->{PATHS}->{DATA};
            my $archive_name  = join '', $p->{image_path}, $wanted, '_', $p->{container}, '_', $p->{tag}, '___', $datestring;
            $archive_name = make_image( $source_folder, $archive_name, '' );

            foreach my $machine ( keys $machines->%* ) {

                $machines->{$machine}->{source} = $archive_name;
                $machines->{$machine}->{target} = $p->{image_path};
            }
        }
        return $machines;
    };

    my $container_pdata_sub = sub() {

        if ( exists( $p->{container} ) && exists( $p->{tag} ) && kexists( $container_cfg, $p->{container}, $p->{tag}, 'config' ) ) {

            my $datestring    = get_tag;
            my $source_folder = $container_cfg->{ $p->{container} }->{ $p->{tag} }->{config}->{DOCKER}->{PATHS}->{PERSISTENT};
            my $filename      = join '', $wanted, '_', $p->{container}, '_', $p->{tag};
            my $archive_name  = join '', $p->{image_path}, $wanted, '_', $p->{container}, '_', $p->{tag}, '___', $datestring, '.tar.xz';

            print_table( 'packing', $source_folder, ': ' );
            store_image( { source => $source_folder, target => $p->{image_path}, filename => $filename, tag => $datestring } );
            say 'OK';

            foreach my $machine ( keys $machines->%* ) {

                $machines->{$machine}->{source} = $archive_name;
                $machines->{$machine}->{target} = $p->{image_path};
            }
        }
        return $machines;
    };

    my $generic_sub = sub ($target) {
        foreach my $machine ( keys $machines->%* ) {
            my $string = join '_', $p->{network}, $machine;
            return unless ( kexists( $images, $wanted, $string, 'latest' ) );
            $machines->{$machine}->{source} = $images->{$wanted}->{$string}->{latest};
            $machines->{$machine}->{target} = $target;
        }
        return $machines;
    };
    my $container_docker_sub = sub () {

        if ( kexists( $images, 'docker', 'all', 'latest' ) ) {
            foreach my $machine ( keys $machines->%* ) {
                $machines->{$machine}->{source} = $images->{docker}->{all}->{latest};
                $machines->{$machine}->{target} = $p->{image_path};
            }
        }
        return $machines;
    };

    my $dispatch = {
        genesis               => sub () { return $generic_sub->( $p->{image_path} ) },
        bootstrap             => sub () { return $generic_sub->('/tmp') },
        image                 => $image_sub,
        $p->{container_pdata} => $container_pdata_sub,
        $p->{container_data}  => $container_data_sub,
        docker                => $container_docker_sub
    };

    return $dispatch->{$wanted_prefix}->() if ( exists( $dispatch->{$wanted_prefix} ) );
    return;
}

###############################################
# Frontend Functions

sub ssh_push ( $mode, $query, @args ) {

    my ( $wanted, $id, $container_fullname ) = @args;

    unless ($id) {
        say 'ERROR: not enough arguments';
        return 1;
    }

    my ( $network, $machine_name ) = split /\//, $id;

    my $group         = $query->('group');
    my $image_path    = $query->('image_path');
    my $container_cfg = $query->('container_cfg');
    my $others        = $query->('others');
    my $mro_user      = $query->('mro_user');
    my $mro_key_path  = $query->('mro_key_path');
    my $p             = {
        mode            => $mode,
        wanted          => $wanted,
        network         => $network,
        group           => $group,
        image_path      => join( '', $image_path, '/' ),
        images          => $query->('images'),
        container_data  => $query->('container_data'),
        container_pdata => $query->('container_pdata'),
    };

    my ( $container_name, $container_tag ) = get_container( $container_cfg, $container_fullname );

    $p->{container} = $container_name if ($container_fullname);
    $p->{tag}       = $container_tag  if ($container_fullname);
    $p->{machine}   = $machine_name   if ($machine_name);

    my $machines = list_machines(
        {
            own_nodes    => $query->('nodes'),
            own_group    => $group,
            other_nodes  => $others->{$network},
            wanted_group => $network,
            mro_user     => $mro_user,
            mro_key      => $mro_key_path,
            mode         => $mode,
        }
    );

    if ( scalar( keys $machines->%* ) == 0 ) {
        say 'ERROR: unknown network or no nodes in group';
        return 1;
    }

    # if there is a node given, see that it exists and delete all but that node from the list
    if ($machine_name) {

        unless ( exists( $machines->{$machine_name} ) ) {
            say "ERROR: machine $machine_name not found";
            return 1;
        }

        # unconventional, but works
        foreach my $entry ( keys $machines->%* ) {
            delete $machines->{$entry} unless ( $entry eq $machine_name );
        }
    }

    $machines = _add_paths( $machines, $container_cfg, $p );

    unless ($machines) {
        say 'ERROR: could not resolve your query';
        return 1;
    }
    foreach my $machine ( keys $machines->%* ) {
        scp_deploy( $machines->{$machine} );
    }
    return;
}

############
sub import_push () {

    my %require_all = (
        image_path   => 'paths data IMAGES',
        nodes        => 'machine nodes',
        group        => 'machine self GROUP',
        others       => 'machine adjacent',
        mro_user     => 'machine self NAMES MRO',
        mro_key_path => 'machine self COMPONENTS SERVICE ssh HOSTKEYS ED25519 PRIVPATH'
    );

    my %require_push = (
        container_data  => 'paths container MAPPINGS DATA',
        container_pdata => 'paths container MAPPINGS PERSISTENT',
        images          => 'state images',
        container_cfg   => 'container',
    );

    my $struct = {
        push => {
            normal => {
                CMD => sub (@arg) {
                    ssh_push( 'normal', @arg );
                },
                DESC => 'push images in normal operation mode',
                HELP => [ 'push normal <image> <network/machine>', 'ie: push normal genesis build/buildhost', 'see \'images state\' for image to deploy' ],
                DATA => { %require_all, %require_push, }
            },
            bootstrap => {
                CMD => sub (@arg) {
                    ssh_push( 'bootstrap', @arg );
                },
                DESC => 'push images in bootstrap operation mode',
                HELP =>
                  [ 'push bootstrap <image> <network/machine>', 'ie: push bootstrap genesis build/buildhost', 'see \'images state\' for image to deploy' ],
                DATA => { %require_all, %require_push, }
            }
        },
    };

    return $struct;
}

1;

