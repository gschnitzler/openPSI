package Plugins::Container::Docker::Container;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists kdelete);
use Tree::Merge qw(add_tree);

our @EXPORT_OK = qw(solve_order get_containers);

###########################################

sub solve_order ( $container, $order ) {

    # to let containers sort out their stopping order on their own,
    # all the containers with START_AFTER (in this case meaning STOP_BEFORE) tell the entries of their START_AFTER
    # all entries of START_AFTER wait for the containers with START_AFTER, therefor, need to be informed to wait.

    # to let containers sort out their starting order on their own,
    # all containers having a START_AFTER wait for the go of the entries of their START_AFTER
    # the other way round, all the entries of all START_AFTER need to tell the containers with a START_AFTER
    # lets give them a list.

    my @not_found = ();

    foreach my $e ( $container->@* ) {

        my $ec         = $e->{DATA}->{config};    # ec means entry_config/container
        my $ec_name    = $ec->{NAME};
        my $solved_dep = 0;
        next unless exists( $ec->{START_AFTER} );

        $ec->{ $order->[0] } = delete( $ec->{START_AFTER} );    # for sanity, rename the hash

        foreach my $listed_container ( keys $ec->{ $order->[0] }->%* ) {

            my $add_timeout = 0;
            foreach my $o ( $container->@* ) {

                my $oc = $o->{DATA}->{config};                  # oc means other_config/container
                if ( $oc->{NAME} eq $listed_container ) {
                    $oc->{ $order->[1] }->{$ec_name} = 1;

                    # timeouts are cumulative, but if there are multiple deps, just add the highest one
                    $add_timeout = $o->{TIMEOUT} if ( $o->{TIMEOUT} > $add_timeout );
                    $solved_dep++;
                }
            }
            $e->{TIMEOUT} = $e->{TIMEOUT} + $add_timeout if ($solved_dep);

            unless ($solved_dep) {
                push @not_found, [ $ec_name, $listed_container ];
                kdelete( $ec, $order->[0], $listed_container );
            }
        }
    }

    my $tree = {};

    foreach my $ref ( $container->@* ) {

        # insert process names, used by task manager
        my $container_name = $ref->{DATA}->{config}->{NAME};
        add_tree( $tree, { $container_name => $ref } );
    }

    return $tree, @not_found;
}

sub get_containers ( $config, @args ) {

    my $container  = shift @args;
    my @containers = ();
    my ( $arg_name, $arg_tag ) = ( '', '' );

    if ($container) {

        ( $arg_name, $arg_tag ) = split( /_/, $container );
        if ( !$arg_name || !$arg_tag || !kexists( $config, $arg_name, $arg_tag ) ) {
            say "ERROR: container $container not found";
            return;
        }
    }

    # containers to start
    foreach my $container_name ( keys $config->%* ) {

        next if ( $arg_name && $container_name ne $arg_name );

        foreach my $container_tag ( keys $config->{$container_name}->%* ) {

            next if ( $arg_tag && $container_tag ne $arg_tag );
            my $container_cfg = $config->{$container_name}->{$container_tag}->{config};

            $container_cfg->{ARGS} = \@args if ( $args[0] );

            push @containers, $container_cfg;
        }
    }

    return @containers;
}

1;
