package Plugins::Build::Filter::Machines::Adjacent;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists);
use Tree::Merge qw(add_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_adjacent);

sub _add_container ( $tree, $components ) {

    return unless exists( $components->{CONTAINER} );

    foreach my $container_name ( keys $components->{CONTAINER}->%* ) {
        foreach my $container_tag ( keys $components->{CONTAINER}->{$container_name}->%* ) {

            my $ad_container = $components->{CONTAINER}->{$container_name}->{$container_tag};
            if ( exists( $ad_container->{ENABLE} ) && $ad_container->{ENABLE} eq 'yes' ) {
                $tree->{CONTAINER}->{$container_name}->{$container_tag}->{ENABLE} = $ad_container->{ENABLE};
            }
        }
    }
    return;
}

sub add_adjacent ( $machine, $clusters ) {

    my $adjacent          = delete $machine->{ADJACENT};
    my $machine_name      = $machine->{NAMES}->{SHORT};
    my $cluster_name      = $machine->{GROUP};
    my $adjacent_filtered = {};

    print_table( 'Add Adjacent Nodes to', "$cluster_name/$machine_name", ': ' );

    if ( !$adjacent || scalar keys $adjacent->%* == 0 ) {
        say 'NO';
        return $adjacent_filtered;
    }

    foreach my $ad_cluster_name ( keys $adjacent->%* ) {

        my $adjacent_cluster = $adjacent->{$ad_cluster_name};
        die "ERROR: Cluster $ad_cluster_name not found." unless ( exists $clusters->{$ad_cluster_name} );
        print "$ad_cluster_name/";

        if ( exists $adjacent_cluster->{any} ) {

            print 'any ';

            foreach my $ad_machine_name ( keys $clusters->{$ad_cluster_name}->%* ) {

                # we only need very specific data, the rest is of no interest or holds secrets
                my $ad_machine = $clusters->{$ad_cluster_name}->{$ad_machine_name};
                my $f_data     = {
                    NETWORK  => dclone $ad_machine->{NETWORK}->{PUBLIC},
                    HOSTNAME => $ad_machine->{NAMES}->{FULL},
                    SSH      => {
                        SSHPORT => $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{SSHPORT},
                        PUB     => $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB}
                    }
                };
                $f_data->{SSH}->{NAT} = dclone $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{NAT}
                  if kexists( $ad_machine, 'COMPONENTS', 'SERVICE', 'ssh', 'NAT' );

                _add_container( $f_data, $clusters->{$ad_cluster_name}->{$ad_machine_name}->{COMPONENTS} );

                $adjacent_filtered->{$ad_cluster_name}->{$ad_machine_name} = $f_data;
                add_tree( $adjacent_filtered->{$ad_cluster_name}->{$ad_machine_name}, $adjacent->{$ad_cluster_name}->{any} );
            }
        }
        else {

            foreach my $ad_machine_name ( keys $adjacent_cluster->%* ) {

                die "ERROR: machine $ad_machine_name not found." unless ( kexists( $clusters, $ad_cluster_name, $ad_machine_name ) );
                print "$ad_machine_name ";

                # we only need very specific data, the rest is of no interest or holds secrets
                my $ad_machine = $clusters->{$ad_cluster_name}->{$ad_machine_name};
                my $f_data     = {
                    NETWORK  => dclone $ad_machine->{NETWORK}->{PUBLIC},
                    HOSTNAME => $ad_machine->{NAMES}->{FULL},
                    SSH      => {
                        SSHPORT => $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{SSHPORT},
                        PUB     => $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB}
                    }
                };
                $f_data->{SSH}->{NAT} = dclone $ad_machine->{COMPONENTS}->{SERVICE}->{ssh}->{NAT}
                  if kexists( $ad_machine, 'COMPONENTS', 'SERVICE', 'ssh', 'NAT' );

                _add_container( $f_data, $ad_machine->{COMPONENTS} );

                $adjacent_filtered->{$ad_cluster_name}->{$ad_machine_name} = $f_data;
                add_tree( $adjacent_filtered->{$ad_cluster_name}->{$ad_machine_name}, $adjacent->{$ad_cluster_name}->{$ad_machine_name} );
            }
        }
    }
    say '';

    return $adjacent_filtered;
}

