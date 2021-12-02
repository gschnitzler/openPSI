package Plugins::Build::Filter::Machines::Container;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists);
use Tree::Slice qw(slice_tree);
use Tree::Search qw(tree_fraction);
use Tree::Merge qw(add_tree clone_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_container);

################################################################################

sub _inherit_secrets ($p) {

    my $wanted    = $p->{wanted_data};
    my $config    = $p->{wanted_container_config};
    my $container = $p->{container_config};

    my @secrets = split( /,/, $wanted );

    foreach my $secret (@secrets) {

        die "ERROR: exposed SECRET $secret not registered in exposing container" unless kexists( $config, 'SECRETS', $secret );
        $container->{SECRETS}->{$secret} = $config->{SECRETS}->{$secret};
    }

    return;
}

sub _find_template($p) {

    my $wanted_template = $p->{wanted_data};
    my $templates_from  = $p->{wanted_container_templates};
    my $templates_to    = $p->{container_templates};

    #   say join( ' ', keys $p->{wanted_container_templates}->%* );
    #   say join( ' ', keys $p->{container_templates}->%* );

    my ( $from_pointer, $to_pointer ) = ( $templates_from, $templates_to );
    my ( $last_from_pointer, $last_to_pointer, $last_key ) = ( $templates_from, $templates_to, '' );
    my @path = ();

    foreach my $key ( split( /\//, $wanted_template ) ) {

        die "ERROR: exposed template $wanted_template does not exist, path so far: ", join( '/', @path ), ", missing: $key"
          unless exists( $from_pointer->{$key} );
        push @path, $key;

        ( $last_from_pointer, $last_to_pointer, $last_key ) = ( $from_pointer, $to_pointer, $key );
        $from_pointer = $from_pointer->{$key};
        $to_pointer   = $to_pointer->{$key};
    }

    return ( $last_to_pointer, $last_from_pointer, $last_key );
}

sub _inherit_copy ($p) {

    my ( $last_to_pointer, $last_from_pointer, $last_key ) = _find_template($p);
    my $to_add->{$last_key} = clone_tree( $last_from_pointer->{$last_key} );
    add_tree( $last_to_pointer, $to_add );

    return;
}

sub _inherit_move ($p) {

    _inherit_copy($p);
    return [ $p->{full_path}->@*, split( /\//, $p->{wanted_data} ) ];
}

sub _inherit_container_config ($p) {

    my $exposed      = $p->{exposed_containers};
    my $config       = $p->{config};
    my $inherit_name = $p->{inherit};
    my @delete       = ();
    my $dispatch     = {
        SECRETS => \&_inherit_secrets,
        COPY    => \&_inherit_copy,
        MOVE    => \&_inherit_move,
    };

    foreach my $entry ( $exposed->@* ) {

        my $from_cf             = $entry->[0];
        my $from_container_name = $entry->[1]->[0];
        my $from_container_tag  = $entry->[1]->[1];

        next unless kexists( $from_cf, 'EXPOSE', $inherit_name);

        foreach my $expose_name ( keys $from_cf->{EXPOSE}->{$inherit_name}->%* ) {

            my $exposed_entry = $from_cf->{EXPOSE}->{$inherit_name}->{$expose_name};
            my ( $exposed_option, $exposed_data ) = split( /:/, $exposed_entry );

            # print " ($from_container_name:$from_container_tag)";

            #       say 'wanted_data: ', $exposed_data;
            #       say 'wanted_container_config: ', join(' ', keys $from_cf->%*);
            #       say 'wanted_container_templates: ', join(' ', keys $config->{$from_container_name}->{templates}->%*);
            #       say 'container_config: ', join(' ', keys $p->{to_config}->%*);
            #       say 'container_templates: ', join(' ', keys $p->{to_templates}->%*);
            push @delete, $dispatch->{$exposed_option}->(
                {
                    wanted_data                => $exposed_data,
                    wanted_container_config    => $from_cf,
                    wanted_container_templates => $config->{$from_container_name}->{$from_container_tag}->{templates},
                    container_config           => $p->{to_config},
                    container_templates        => $p->{to_templates},

                    # templates is hardwired in wanted_container_templates here and to_templates in _inherit
                    full_path => [ $from_container_name, $from_container_tag, 'templates' ]
                }
            );
        }
    }
    return @delete;
}

sub _inherit( $cluster_containers) {

    my $inherit_cond = sub ($branch) {
        return 1 if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{INHERIT} );
        return 0;
    };
    my $expose_cond = sub ($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{EXPOSE} ) );
        return 0;
    };

    # delete all the expose/inherit statements
    my $clean_cond = sub ($branch) {
        delete $branch->[0]->{EXPOSE}  if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{EXPOSE} );
        delete $branch->[0]->{INHERIT} if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{INHERIT} );
        return 0;
    };

    my @inherit_containers = slice_tree( $cluster_containers, $inherit_cond );

    foreach my $item (@inherit_containers) {

        my $container_config    = $item->[0];
        my $container_name      = $item->[1]->[0];
        my $container_tag       = $item->[1]->[1];
        my $container_templates = $cluster_containers->{$container_name}->{$container_tag}->{templates};
        my @delete_templates    = ();

        # find container root and root of all containers of this machine
        # this is important, as we only want to resolve statements on a single machine
        #$this_container    = $this_container->{$_}    for ( @{ $item->[1] }[ 0 .. $#{ $item->[1] } - 1 ] );
        #$machine_container = $machine_container->{$_} for ( @{ $item->[1] }[ 0 .. $#{ $item->[1] } - 3 ] );
        my @exposed_containers = slice_tree( $cluster_containers, $expose_cond );

        foreach my $inherit_name ( keys $container_config->{INHERIT}->%* ) {

            next unless ( $container_config->{INHERIT}->{$inherit_name} eq 'yes' );

            #print_table( 'Resolve Container', ' ', ": $container_name/$container_tag/$inherit_name" );

            push @delete_templates,
              _inherit_container_config(
                {
                    inherit            => $inherit_name,
                    to_config          => $container_config,
                    to_templates       => $container_templates,
                    exposed_containers => \@exposed_containers,
                    config             => $cluster_containers,
                }
              );

            #say '';
        }
        slice_tree( $cluster_containers, $clean_cond );

        #say keys $machine_container->%*;

        # delete all the exposed templates that should have been MOVEd
        foreach my $entry (@delete_templates) {

            my ( $ref, $key ) = tree_fraction( { tree => $cluster_containers, keys => $entry } );
            delete $ref->{$key};
        }
    }

    return $cluster_containers;
}

sub _filter_container_ips ( $if_address, $container_network ) {

    $if_address =~ s/[.]\d+$//x;

    foreach my $container_network_name ( keys $container_network->%* ) {

        my $container_ip = $container_network->{$container_network_name};
        $container_network->{$container_network_name} = join( '.', $if_address, $container_ip );

    }
    return $container_network;
}

sub _filter_container_maps ( $container, $containers ) {

    return $container unless kexists( $container, 'DOCKER', 'MAP');

    my @maps = slice_tree(
        $container->{DOCKER}->{MAP},
        sub ($b) {
            return 1 unless ref $b->[0];
            return 0;
        }
    );

    $container->{DOCKER}->{MAP} = {};    # override it

    for my $e (@maps) {

        my ( $cn, $real_ct, $cv ) = $e->[1]->@*;
        my $p = $e->[0];

        die "ERROR: MAP container '$cn' does not exists" unless exists $containers->{$cn};

        my @cts = ( $real_ct eq 'any' ) ? keys $containers->{$cn}->%* : ($real_ct);

        for my $ct (@cts) {
            die "ERROR: MAP container tag '$ct' does not exist ($cn:$real_ct)" unless kexists( $containers, $cn, $ct);
            die "ERROR: MAP container volume path '$cv' does not exist ($cn:$real_ct)" unless kexists( $containers, $cn, $ct, 'DOCKER', 'PATHS', $cv);
            my $target_path = join( '/', $cn, $ct, $cv, $p );    # this leaves untranslated $cv. so PERSISTENT instead of pdata.
            my $source_path = join( '/', $containers->{$cn}->{$ct}->{DOCKER}->{PATHS}->{$cv}, $p );
            $container->{DOCKER}->{MAP}->{$target_path} = $source_path;
        }
    }
    return $container;
}

sub _get_container ( $machine, $container, $images ) {

    my $container_templates = $container->{templates};
    my $container_config    = $container->{config};
    my $image_config        = $images->{config};
    my $machine_name        = $machine->{NAMES}->{SHORT};
    my $cluster_name        = $machine->{GROUP};
    my $machine_container   = $machine->{COMPONENTS}->{CONTAINER};
    my $counter             = 0;
    my $container_togo      = {};

    print_table( 'Add Container', "$cluster_name/$machine_name", ': ' );
    foreach my $required_container_name ( keys( $machine_container->%* ) ) {

        #print "$required_container_name(";

        foreach my $required_container_tag ( keys( $machine_container->{$required_container_name}->%* ) ) {

            next
              if ( !kexists( $machine_container, $required_container_name, $required_container_tag, 'ENABLE' )
                || $machine_container->{$required_container_name}->{$required_container_tag}->{ENABLE} ne 'yes' );

            my $rc_nametag = join( '_', $required_container_name, $required_container_tag );
            $counter++;

            #print "$required_container_tag,";

            die "ERROR: Container $rc_nametag not found " unless kexists( $container_config, $required_container_name, $required_container_tag );

            my $container_image = $container_config->{$required_container_name}->{$required_container_tag}->{DOCKER}->{IMAGE};

            die "ERROR: Container Image $container_image of Container $rc_nametag not found." unless exists( $image_config->{$container_image} );

            my $this_container_config =
              _filter_container_maps( dclone( $container_config->{$required_container_name}->{$required_container_tag} ), $container_config );
            $this_container_config->{NETWORK}->{IP} =
              _filter_container_ips( $machine->{NETWORK}->{INTERN}->{ADDRESS}, $this_container_config->{NETWORK}->{IP} );

            # this is already dcloned, so deleting from $machine_container does not work, and we don't want to have it in 2 places
            # $this_container_config->{OPTIONS} = delete $machine_container->{$required_container_name}->{$required_container_tag}->{OPTIONS}
            #  if exists $machine_container->{$required_container_name}->{$required_container_tag}->{OPTIONS};

            $container_togo->{$required_container_name}->{$required_container_tag} = {
                config    => $this_container_config,
                templates => $container_templates->{$required_container_name}->{$required_container_tag},
            };
        }
    }

    say $counter;
    return $container_togo;
}

sub add_container ( $machine, $container, $images ) {

    return _inherit _get_container( $machine, $container, $images );
}

