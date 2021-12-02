package Plugins::Deploy::Cmds::Remote;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Deploy::Libs::Machines qw(list_machines);
use Plugins::Deploy::Libs::SSH qw(ssh_cmd);

our @EXPORT_OK = qw(import_remote);

sub remote ( $mode, $query, @args ) {

    if ( !@args ) {
        say 'ERROR: no argument given';
        return 1;
    }

    my ( $network, $machine ) = split /\//, shift @args;
    my $cmd = join ' ', @args;

    unless ($network) {
        say 'no/invalid network';
        return 1;
    }

    my $group    = $query->('group');
    my $nodes    = $query->('nodes');
    my $others   = $query->('others');
    my $mro_user = $query->('mro_user');
    my $mro_key  = $query->('mro_key_path');
    my $machines = list_machines(
        {
            own_nodes    => $nodes,
            own_group    => $group,
            other_nodes  => $others->{$network},
            wanted_group => $network,
            mro_user     => $mro_user,
            mro_key      => $mro_key,
            mode         => $mode,
        }
    );

    if ( scalar( keys $machines->%* ) == 0 ) {
        say 'ERROR: unknown network or no nodes in group';
        return 1;
    }

    # if there is a node given, see that it exists and delete all but that node from the list
    if ($machine) {

        unless ( exists( $machines->{$machine} ) ) {
            say "ERROR: machine $machine not found";
            return 1;
        }

        # unconventional, but works
        foreach my $entry ( keys $machines->%* ) {
            delete $machines->{$entry} unless ( $entry eq $machine );
        }
    }

    # execute for every machine in the list
    foreach my $machine ( keys $machines->%* ) {
        ssh_cmd( $machines->{$machine}, $cmd );
    }
    return;
}

###############################################
# Frontend Functions

sub import_remote () {

    my %all_remote = (
        nodes        => 'machine nodes',
        others       => 'machine adjacent',
        group        => 'machine self GROUP',
        mro_user     => 'machine self NAMES MRO',
        mro_key_path => 'machine self COMPONENTS SERVICE ssh HOSTKEYS ED25519 PRIVPATH'
    );

    my $struct = {
        remote => {
            normal => {
                CMD  => sub (@arg) { remote( 'normal', @arg ) },
                DESC => 'runs a command/open a shell on a remote machine in normal operation mode',
                HELP => [ 'remote normal <machine> <commands>', 'ie: remote normal build/buildhost sudo genesis help' ],
                DATA => {%all_remote}
            },
            bootstrap => {
                CMD  => sub (@arg) { remote( 'bootstrap', @arg ) },
                DESC => 'runs a command/open a shell on a remote machine in bootstrap operation mode',
                HELP => [ 'remote bootstrap <machine> <commands>', 'ie: remote bootstrap build/buildhost sudo genesis help' ],
                DATA => {%all_remote}
            }
        }
    };

    return $struct;

}
1;

