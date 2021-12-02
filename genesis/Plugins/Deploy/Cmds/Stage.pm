package Plugins::Deploy::Cmds::Stage;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Tag qw(get_tag);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_system run_open);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use IO::Config::Check qw(dir_exists);

use Plugins::Deploy::Libs::Machines qw(list_machines);
use Plugins::Deploy::Libs::Container qw(get_container);
use Plugins::Deploy::Libs::Image qw(make_image);
use Plugins::Deploy::Libs::SSH qw(scp_deploy);

our @EXPORT_OK = qw(import_stage);

#############

sub _find_containers ( $config, $wanted_container, $wanted_tag ) {

    my $found = {};

    foreach my $node_name ( keys $config->%* ) {
        my $n = $config->{$node_name};
        next unless kexists( $n, 'COMPONENTS', 'CONTAINER', $wanted_container, $wanted_tag );
        next unless $n->{COMPONENTS}->{CONTAINER}->{$wanted_container}->{$wanted_tag}->{ENABLE} eq 'yes';
        $found->{$node_name} = 1;
    }
    return $found;
}

sub _mounted($search_string) {

    # do not use mount | grep $search_string
    # if $search_string is not found or empty, grep returns EC:1, causing open to fail.
    # just get the list, do the rest in perl
    # there is another issue that randomly causes open to fail. seems to happen for a set period of time, then goes away again.
    # mount outputs while and after this happened are the same. last time i was not fast enough to read $? and $!
    # so i added them below. hopefully this gives a lead

    for my $line ( run_open 'mount' ) {
        return $line if ( $line =~ /$search_string/ );
    }
    return;
}

sub _nodes ( $mkimage, $found_nodes, $image_path, $lm ) {

    my $archive_path = $mkimage->();
    my $machines     = list_machines($lm);

    # then deploy those images to those nodes
    foreach my $node_name ( keys $machines->%* ) {

        unless ( exists $found_nodes->{$node_name} ) {
            delete $machines->{$node_name};
            next;
        }

        $machines->{$node_name}->{source} = $archive_path;
        $machines->{$node_name}->{target} = $image_path;
        scp_deploy( $machines->{$node_name} );
    }

    return;
}

sub _adjacent ( $mkimage, $found_adjacent, $image_path, $adjacent, $lm ) {

    my $archive_path = $mkimage->();
    my $all_machines = {};
    foreach my $adj_group ( keys $found_adjacent->%* ) {

        my $adj_names = $found_adjacent->{$adj_group};
        $lm->{other_nodes}  = $adjacent->{$adj_group};
        $lm->{wanted_group} = $adj_group;
        my $machines = list_machines($lm);

        # then deploy those images to those nodes
        foreach my $node_name ( keys $machines->%* ) {

            if ( !exists( $adj_names->{$node_name} ) ) {
                delete $machines->{$node_name};
                next;
            }

            $machines->{$node_name}->{source} = $archive_path;
            $machines->{$node_name}->{target} = $image_path;
        }
        add_tree( $all_machines, $machines );
    }

    foreach my $machine ( keys $all_machines->%* ) {
        scp_deploy( $all_machines->{$machine} );
    }
    return;
}

sub _check_source_folder($args_source_folder) {

    if ($args_source_folder) {

        if ( $args_source_folder !~ /^\/home/ ) {
            say 'ERROR: Source folder is not in home directory or not an abolute path';
            return 1;
        }
        unless ( dir_exists $args_source_folder ) {
            say 'ERROR: Source folder is not a directory';
            return 1;
        }
    }

    return 0;
}

sub _check_stage_tag ( $stage, $container_tag ) {

    if ( !exists( $stage->{$container_tag} ) || !$stage->{$container_tag} ) {

        say "ERROR: stage $container_tag does not exist or has no stage above";
        return 1;
    }
    return 0;
}

###############################################
# Frontend Functions

sub ssh_stage ( $query, @args ) {

    my $container_fullname = shift @args;
    my $args_source_folder = shift @args;
    my $container_cfg      = $query->('container_cfg');
    my $nodes              = $query->('nodes');
    my $adjacent           = $query->('others');
    my $stage              = $query->('stage');
    my $image_path         = $query->('image_path');
    my $group              = $query->('group');
    my $images             = $query->('images');
    my $mro_user           = $query->('mro_user');
    my $mro_key_path       = $query->('mro_key_path');
    my $failed             = 0;

    ############################### CHECKS ################################

    my ( $container_name, $container_tag ) = get_container( $container_cfg, $container_fullname );

    if ( !$container_name || !$container_tag ) {
        say 'ERROR: unknown container';
        return 1;
    }

    $failed = _check_source_folder($args_source_folder);
    return $failed if $failed;

    $failed = _check_stage_tag( $stage, $container_tag );
    return $failed if $failed;

    ################################# / CHECKS ####################################

    print_table( 'Staging', $container_fullname, ': ' );

    my $dest_stage = $stage->{$container_tag};
    $dest_stage = $container_tag if ($args_source_folder);    # keep the image name
    say $dest_stage;

    my $datestring = get_tag;
    my $mkimage    = sub () {

        my $source_folder = '';
        my $c_cfg         = $container_cfg->{$container_name}->{$container_tag};

        # override this with the user given source folder
        if ($args_source_folder) {
            $source_folder = $args_source_folder;
        }
        else {
            $source_folder = $c_cfg->{config}->{DOCKER}->{PATHS}->{DATA};
        }

        my $archive_name = join '', $image_path, '/', 'data', '_', $container_name, '_', $dest_stage, '___', $datestring;

        return make_image( $source_folder, $archive_name, '' ) if ( !_mounted $source_folder );

        die 'ERROR: mounted image does not exist' unless kexists( $images, 'data', $container_fullname, 'latest' );
        my $old_image = $images->{data}->{$container_fullname}->{latest};
        my $new_image = join '', $archive_name, '.xz';
        run_system "cp -fp $old_image $new_image";
        return $new_image;
    };

    my $find_container = sub ($branch) {

        if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{CONTAINER} ) ) {
            return 1;
        }
        return 0;
    };

    ################################### ACTUAL EXECUTION ############################

    print_table( 'Location of Stage', $dest_stage, ': ' );

    my $found_nodes    = _find_containers( $nodes, $container_name, $dest_stage );
    my $found_adjacent = {};

    foreach my $entry ( slice_tree( $adjacent, $find_container ) ) {

        my $adj_host_cf = $entry->[0];

        if ( kexists( $adj_host_cf, 'CONTAINER', $container_name, $dest_stage, 'ENABLE' )
            && $adj_host_cf->{CONTAINER}->{$container_name}->{$dest_stage}->{ENABLE} eq 'yes' )
        {
            $found_adjacent->{ $entry->[1]->[0] }->{ $entry->[1]->[1] } = 1;
        }
    }

    # stage it local
    if ( kexists( $container_cfg, $container_name, $dest_stage ) ) {
        say 'local';
        $mkimage->();
        return;
    }
    elsif ( scalar keys $found_nodes->%* != 0 ) {

        say 'node';
        _nodes(
            $mkimage,
            $found_nodes,
            $image_path,
            {
                own_nodes    => $nodes,
                own_group    => $group,
                other_nodes  => {},
                wanted_group => $group,
                mro_user     => $mro_user,
                mro_key      => $mro_key_path,
                mode         => 'normal',
            }
        );
        return;
    }
    elsif ( scalar keys $found_adjacent->%* > 0 ) {

        say 'adjacent';
        _adjacent(
            $mkimage,
            $found_adjacent,
            $image_path,
            $adjacent,
            {
                own_nodes    => {},
                own_group    => $group,
                other_nodes  => {},
                wanted_group => '',
                mro_user     => $mro_user,
                mro_key      => $mro_key_path,
                mode         => 'normal',
            }
        );
        return;
    }

    say 'ERROR: something went wrong';
    return 1;
}
#################

sub import_stage () {

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
        stage => {
            CMD  => \&ssh_stage,
            DESC => 'stage container data',
            HELP => [
                'usage:',
                'stage <container_name>',
                'creates an image of <container_name> data directory.',
                'if the next stage is not local, the image is pushed'
            ],
            DATA => { %require_all, %require_push, stage => 'machine self STAGE', }
        }
    };

    return $struct;
}

1;

