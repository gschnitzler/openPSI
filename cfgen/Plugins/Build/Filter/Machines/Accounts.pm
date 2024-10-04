package Plugins::Build::Filter::Machines::Accounts;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use Tree::Merge qw(add_tree);
use Tree::Slice qw(slice_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_accounts);

# we look for ADJACENT entries of every machine, then we just reverse the order
# meaning: we have a structure of machines who know other machines (ADJACENT)
# now, we want the other machines to know, who is ADJACENT to them
sub _adjacent_to ( $clusters ) {

    my $adjacent_to = {};
    my $cond        = sub ($branch) {

        # 6 because the keys are (at least) cluster,machine,MACHINE.adjacent,adjacent_cluster,adjacent_machine,
        return 0 if scalar $branch->[1]->@* != 6;       ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        return 1 if $branch->[1]->[3] eq 'adjacent';    ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        return 0;
    };
    my $add = sub ( $l, $r ) {

        # while we are at it, add stuff we need later
        $l->{HOST_UID}    = $r->{HOST_UID};
        $l->{CLUSTER_GID} = $r->{CLUSTER_GID};
        $l->{MRO}         = $r->{NAMES}->{MRO};
        $l->{SSH}->{PUB}  = $r->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB};
    };

    foreach my $entry ( slice_tree( $clusters, $cond ) ) {

        my $cluster_name     = $entry->[1]->[0];
        my $machine_name     = $entry->[1]->[1];
        my $adjacent_cluster = $entry->[1]->[4];                                                 ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        my $adjacent_machine = $entry->[1]->[5];                                                 ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        my $cm               = $clusters->{$cluster_name}->{$machine_name}->{machine}->{self};
        my $adjm = $adjacent_to->{$adjacent_cluster}->{$adjacent_machine}->{$cluster_name}->{$machine_name} = {};
        $add->( $adjm, $cm );
    }

    return $adjacent_to;
}

sub _add_node_accounts ( $machine, $nodes ) {

    my $t                    = {};
    my $machine_name         = $machine->{NAMES}->{SHORT};
    my $cluster_name         = $machine->{GROUP};
    my $cluster_machine_name = "$cluster_name/$machine_name";
    print_table( 'Add Node Accounts to', $cluster_machine_name, ': ' );

    foreach my $node_name ( keys $nodes->%* ) {

        print "$node_name ";
        my $node        = $nodes->{$node_name};
        my $mro_account = $node->{NAMES}->{MRO};

        $t->{MACHINE_ACCOUNTS}->{USERS}->{$mro_account} = {
            SHELL  => '/usr/bin/bash',
            GROUPS => 'wheel',
            GID    => $node->{CLUSTER_GID},
            UID    => $node->{HOST_UID},
            NAME   => $mro_account,
            HOME   => "/home/$mro_account",
            SSH    => { PUB => $node->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB}, }
        };
    }

    ( scalar keys $nodes->%* == 0 ) ? say 'NO' : say '';
    return $t;
}

sub _add_mro_accounts ( $machine, $adjacent_to ) {

    my $machine_name         = $machine->{NAMES}->{SHORT};
    my $cluster_name         = $machine->{GROUP};
    my $own_mro              = $machine->{NAMES}->{MRO};
    my $cluster_machine_name = "$cluster_name/$machine_name";
    my $hit                  = 0;
    my $t                    = {};
    my $cond                 = sub ($branch) {

        # 4 because the keys are (at least) cluster,machine,adjacent_cluster,adjacent_machine,
        return 0 if scalar $branch->[1]->@* != 4;    ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)

        # the scalar == 4 is used to break, as matching the first values of branch will also match the rest.
        return 1
          if $branch->[1]->[0] eq $cluster_name
          && $branch->[1]->[1] eq $machine_name
          && scalar $branch->[1]->@* == 4;           ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        return 0;
    };

    print_table( 'Add MRO Accounts to', $cluster_machine_name, ': ' );

    foreach my $entry ( slice_tree( $adjacent_to, $cond ) ) {

        $hit++;

        my $other_machine_cf   = $entry->[0];
        my $other_cluster_name = $entry->[1]->[2];
        my $other_machine_name = $entry->[1]->[3];           ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        my $other_machine_mro  = $other_machine_cf->{MRO};

        print "$other_cluster_name/$other_machine_name ";

        add_tree $t,
          {
            MACHINE_ACCOUNTS => {
                USERS => {
                    $other_machine_mro => {
                        SHELL  => '/usr/bin/bash',
                        GROUPS => 'wheel,machines',
                        GID    => $other_machine_cf->{CLUSTER_GID},
                        UID    => $other_machine_cf->{HOST_UID},
                        NAME   => $other_machine_mro,
                        HOME   => "/home/$other_machine_mro",
                        SSH    => { PUB => $other_machine_cf->{SSH}->{PUB}, }
                    }
                },
            }
          };
    }

    # also add the machine itself to the list, so a machines mro account is added to it.
    # we need the machines uid/gid to exist for various reasons (priv dropping, chown etc)
    # no ssh key required

    add_tree $t, {
        MACHINE_ACCOUNTS => {
            USERS => {
                $own_mro => {
                    SHELL  => '/usr/bin/nologin',
                    GROUPS => 'machines,wheel',          # machines is the base for all the machines. wheel needed as this user runs dio
                    GID    => $machine->{CLUSTER_GID},
                    UID    => $machine->{HOST_UID},
                    NAME   => $own_mro,
                    HOME   => "/home/$own_mro",
                    SSH    => { PUB => '#' },
                }
            }
        },
        USER_ACCOUNTS => { GROUPS => { $own_mro => { GID => $machine->{CLUSTER_GID} } } },
    };

    ($hit) ? say '' : say 'NO';
    return $t;
}

sub _add_user_accounts ( $machine, $accounts ) {

    my $machine_name         = $machine->{NAMES}->{SHORT};
    my $cluster_name         = $machine->{GROUP};
    my $cluster_machine_name = "$cluster_name/$machine_name";
    my $t                    = {};

    print_table( 'Add User Accounts to', $cluster_machine_name, ': ' );

    add_tree $t, $accounts->{$cluster_name}->{$machine_name} if ( exists $accounts->{$cluster_name}->{$machine_name} );
    add_tree $t, $accounts->{$cluster_name}->{any}           if ( exists $accounts->{$cluster_name}->{any} );

    print "$_ " for keys $t->{USER_ACCOUNTS}->{USERS}->%*;

    ( scalar keys $t->{USER_ACCOUNTS}->{USERS}->%* == 0 ) ? say 'NO' : say '';

    return $t;
}

sub add_accounts ( $clusters, $accounts ) {

    my $tree        = {};
    my $adjacent_to = _adjacent_to($clusters);

    foreach my $cluster_name ( keys( $clusters->%* ) ) {

        my $cluster = $clusters->{$cluster_name};

        foreach my $machine_name ( keys $cluster->%* ) {

            my $machine  = $cluster->{$machine_name}->{machine}->{self};
            my $nodes    = $cluster->{$machine_name}->{machine}->{nodes};
            my $adjacent = $cluster->{$machine_name}->{machine}->{adjacent};
            add_tree $tree, { $cluster_name => { $machine_name => { machine => { self => _add_user_accounts( $machine, $accounts ) } } } };
            add_tree $tree, { $cluster_name => { $machine_name => { machine => { self => _add_node_accounts( $machine, $nodes ) } } } };
            add_tree $tree, { $cluster_name => { $machine_name => { machine => { self => _add_mro_accounts( $machine, $adjacent_to ) } } } };

            #add_tree $tree, { $cluster_name => { $machine_name => { machine => { self => _add_known_hosts( $machine, $nodes, $adjacent ) } } } };
        }
    }
    return $tree;
}
