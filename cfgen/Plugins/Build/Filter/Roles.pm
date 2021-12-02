package Plugins::Build::Filter::Roles;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use PSI::Console qw(print_table);
use Tree::Search qw(tree_fraction);

our @EXPORT_OK = qw(apply_role);

#########

sub _drop_entry ( $key_string, $tree ) {

    # '*' only makes sense when its the only entry.
    return {} if ( $key_string eq '*' );
    my ( $last_pointer, $last_key ) = tree_fraction( { tree => $tree, keys => [ split( /\//, $key_string ) ] } );
    delete $last_pointer->{$last_key};
    return $tree;
}

sub _drop_config ( $config, $drop_config ) {

    foreach my $drop_config_key ( keys $drop_config->%* ) {

        my $drop_string = $drop_config->{$drop_config_key};
        die "ERROR: role requires to drop config section '$drop_config_key', but there is no such section" unless exists $config->{$drop_config_key};

        foreach my $entry ( split( /,/, $drop_string ) ) {
            $config->{$drop_config_key} = _drop_entry( $entry, $config->{$drop_config_key} );
        }
    }
    return;
}

sub _use_plugin ( $machine, $use_plugin ) {

    my $plugins = $machine->{genesis}->{Plugins};

    foreach my $plugin_name ( keys $plugins->%* ) {

        next if $plugin_name eq '..';    # ignore directory modes
        delete $plugins->{$plugin_name} if ( !exists $use_plugin->{$plugin_name} || $use_plugin->{$plugin_name} ne 'yes' );
    }

    return;
}

sub apply_role ( $config, $roles, $genesis ) {

    foreach my $cluster_name ( keys( $config->%* ) ) {

        my $cluster = $config->{$cluster_name};

        foreach my $machine_name ( keys $cluster->%* ) {

            my $machine       = $cluster->{$machine_name};
            my $machine_cf    = $cluster->{$machine_name}->{machine};
            my $machine_name  = $machine_cf->{self}->{NAMES}->{SHORT};
            my $cluster_name  = $machine_cf->{self}->{GROUP};
            my $machine_roles = $machine_cf->{self}->{COMPONENTS}->{ROLES};

            $machine->{genesis} = dclone $genesis;

            print_table( 'Applying Roles to', "$cluster_name/$machine_name", ': ' );

            die 'ERROR: no roles configured' if ( scalar keys $machine_roles->%* < 1 );
            die 'ERROR: too many roles configured' if ( scalar keys $machine_roles->%* > 1 );

            foreach my $role_name ( keys $machine_roles->%* ) {

                die "ERROR: unknown role $role_name" unless exists( $roles->{$role_name} );
                _drop_config( $machine, $roles->{$role_name}->{DROP_CONFIG} );
                _use_plugin( $machine->{genesis}, $roles->{$role_name}->{USE_PLUGINS} );
                print "$role_name ";
            }
            say '';
        }
    }
    return;
}
