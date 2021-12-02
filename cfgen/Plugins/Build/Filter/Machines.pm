package Plugins::Build::Filter::Machines;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kdelete);
use Tree::Merge qw(add_tree override_tree);

use Plugins::Build::Filter::Machines::Galera qw(expand_galera);
use Plugins::Build::Filter::Machines::Container qw(add_container);
use Plugins::Build::Filter::Machines::Accounts qw(add_accounts);
use Plugins::Build::Filter::Machines::Adjacent qw(add_adjacent);
use Plugins::Build::Filter::Machines::Nodes qw(add_nodes);

our @EXPORT_OK = qw(add_machines);

sub add_machines ( $clusters, $container, $images, $accounts ) {

    my $tree = {};

    # its very confusing to deal with $cluster and $tree, dcloning etc
    # so lets create the base structure first, and alter/expand later
    foreach my $cluster_name ( keys( $clusters->%* ) ) {

        my $cluster = $clusters->{$cluster_name};

        foreach my $machine_name ( keys $cluster->%* ) {

            my $machine = $cluster->{$machine_name};

            $tree->{$cluster_name}->{$machine_name} = {
                machine => {
                    self     => dclone $cluster->{$machine_name},
                    nodes    => add_nodes( dclone($cluster), $cluster_name, $machine_name ),
                    adjacent => add_adjacent( dclone($machine), dclone($clusters) ),
                },
                container => add_container( dclone $cluster->{$machine_name}, dclone $container, $images )
            };

            kdelete( $tree, $cluster_name, $machine_name, 'machine', 'self', 'ADJACENT' );    # as its decloned here, can not be done anywhere else
        }
    }

    # now that we gathered the basic structure, lets apply the rest of the filters.
    override_tree $tree, expand_galera($tree);
    add_tree $tree, add_accounts( $tree, $accounts );

    return $tree;
}

