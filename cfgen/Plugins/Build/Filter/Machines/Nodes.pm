package Plugins::Build::Filter::Machines::Nodes;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_nodes);

#########

sub add_nodes ( $cluster, $cluster_name, $machine_name ) {

    my $nodes = {};
    print_table( 'Add Cluster Nodes to', "$cluster_name/$machine_name", ': ' );

    foreach my $node_name ( keys $cluster->%* ) {

        next if ( $node_name eq $machine_name );
        print $node_name, ' ';
        $nodes->{$node_name} = dclone $cluster->{$node_name};
    }

    delete $nodes->{$_}->{ADJACENT} for ( keys $nodes->%* );

    print 'NO' if scalar keys $nodes->%* == 0;
    say '';

    return $nodes;
}
