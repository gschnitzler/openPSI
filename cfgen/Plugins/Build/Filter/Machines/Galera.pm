package Plugins::Build::Filter::Machines::Galera;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists);
use Tree::Slice qw(slice_tree);
use Tree::Build qw(build_tree_data);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(expand_galera);

#########################################

sub _get_options ($clusters) {

    # search tree for OPTIONS->GALERA and MARIABACKUP_PW. content of OPTIONS is optional, but mariadbs templates will fail if not present.
    # this gives us hacky checking.

    my @options    = ();
    my $slice_cond = sub ($b) {
        return 1
          if ref $b->[0] eq 'HASH'
          && exists $b->[0]->{ENABLE}
          && kexists( $b->[0], 'OPTIONS', 'GALERA' )
          && kexists( $b->[0], 'OPTIONS', 'MARIABACKUP_PW' );
        return 0;
    };

    foreach my $e ( slice_tree( $clusters, $slice_cond ) ) {
        push @options, $e if $e->[1]->[3] eq 'self';    # ignore 'node'
    }

    return @options;
}

sub _build_option_tree(@options) {

    my $option_tree  = {};
    my $option_trees = ();
    my $build_cond   = sub ( $k, $h, $p ) {
        return dclone $h;
    };

    for my $e (@options) {

        my $cluster   = $e->[1]->[0];
        my $machine   = $e->[1]->[1];
        my $tag       = $e->[1]->[-1];
        my $container = $e->[1]->[-2];
        build_tree_data( $option_tree, $build_cond, [ $e->[0], [ $container, $tag, $cluster, $machine ] ] );
    }
    return $option_tree;
}

sub expand_galera ( $clusters ) {

    my @options     = _get_options($clusters);
    my $option_tree = _build_option_tree(@options);
    my $tree        = {};

# deep nesting is inelegant, but it does the job. I considered more functional approaches, but the code turned out very complex very fast, while simultaneously getting slower
# all that's done here is some remapping and expanding values from one tree to the other. nothing to write home about.
    for my $container_name ( keys $option_tree->%* ) {
        for my $container_tag ( keys $option_tree->{$container_name}->%* ) {
            for my $cluster_name ( keys $option_tree->{$container_name}->{$container_tag}->%* ) {
                my $c        = $option_tree->{$container_name}->{$container_tag}->{$cluster_name};
                my $node_ips = {};

                foreach my $machine_name ( keys $c->%* ) {
                    die 'ERROR: mixed up config' unless kexists( $clusters, $cluster_name, $machine_name, 'container', $container_name, $container_tag );
                    die 'ERROR: disabled container config'
                      unless kexists( $clusters, $cluster_name, $machine_name, 'container', $container_name, $container_tag, 'config', 'NETWORK', 'IP', 'main' );
                    $node_ips->{$machine_name} =
                      $clusters->{$cluster_name}->{$machine_name}->{container}->{$container_name}->{$container_tag}->{config}->{NETWORK}->{IP}->{main};
                }

                for my $machine_name ( keys $c->%* ) {

                    # always set defaults, needed to prevent template check errors
                    # because of the wsrep templates, configuration needs to be added to any machine.
                    # so even if galera is not used, the machine needs dummy config anyway.
                    my $container_options = {
                        GALERA         => 'no',
                        SELF           => 'disabled',
                        NODES          => 'disabled',
                        MARIABACKUP_PW => 'disabled',
                    };
                    my $container_settings = $c->{$machine_name};
                    my $machine_container  = $clusters->{$cluster_name}->{$machine_name}->{container}->{$container_name}->{$container_tag};
                    my @nodes              = ();

                    print_table( 'Add Galera Cluster:', "$cluster_name/$machine_name:$container_name\_$container_tag", ': ' );

                    $container_options->{MARIABACKUP_PW} = $container_settings->{OPTIONS}->{MARIABACKUP_PW} if ( $container_settings->{ENABLE} eq 'yes' );

                    if ( kexists( $container_settings, 'OPTIONS', 'GALERA' ) && $container_settings->{OPTIONS}->{GALERA} eq 'yes' ) {

                        $container_options->{GALERA} = $container_settings->{OPTIONS}->{GALERA};

                        foreach my $node_name ( keys $node_ips->%* ) {

                            my $container_ip = $node_ips->{$node_name};

                            if ( $node_name ne $machine_name ) {
                                push @nodes, $container_ip;
                                next;
                            }
                            print "$container_ip ";
                            $container_options->{SELF} = $container_ip;
                        }

                        my $joined_nodes = join( ',', @nodes );
                        say '(', $joined_nodes, ')';
                        $container_options->{NODES} = $joined_nodes;
                    }
                    else {
                        say 'NO';
                    }
                    $tree->{$cluster_name}->{$machine_name}->{container}->{$container_name}->{$container_tag}->{config}->{OPTIONS} = $container_options;
                }
            }
        }
    }

    return dclone $tree;
}
