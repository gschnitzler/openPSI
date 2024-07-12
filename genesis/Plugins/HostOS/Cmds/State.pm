package Plugins::HostOS::Cmds::State;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table print_line);

our @EXPORT_OK = qw(import_state);

#############################################

sub _get_accounts ($shadow) {

    my @accounts = ();

    foreach my $k ( sort keys $shadow->%* ) {
        push @accounts, $k if ( $shadow->{$k}->{PW} ne '!' && $shadow->{$k}->{PW} ne '*' );
    }
    return join( ' ', @accounts );
}

sub _state ( $query, @args ) {

    my $chroot   = $query->('state chroot');
    my $cursys   = $query->('state root current');
    my $tarsys   = $query->('state root target');
    my $name     = $query->('name');
    my $group    = $query->('group');
    my $releases = $query->('state release');
    my $user     = $query->('state user');
    my $others   = scalar keys $query->('nodes')->%*;
    my $sysacc   = _get_accounts( $user->{shadow} );

    print_line('HostOS System State');
    print_table( 'Myself:',          ' ',           ": $name\n" );
    print_table( 'Group:',           ' ',           ": $group\n" );
    print_table( 'Others in Group:', ' ',           ": $others\n" );
    print_table( 'System:',          'current',     ": $cursys\n" );
    print_table( 'System:',          'target',      ": $tarsys\n" );
    print_table( 'System:',          'is Chrooted', ": $chroot\n" );
    print_table( 'System:',          'users',       ": $sysacc\n\n" );
    print_table( 'Image Releases:',  ' ',           "\n" );

    foreach my $key ( keys $releases->%* ) {
        my $value = $releases->{$key};
        print_table( $key, ' ', ": $value\n" );
    }

    print_line('');    # '' needed for signatures
    say '';

    return;
}

###############################################

sub import_state () {

    my $struct = {
        hostos => {
            state => {
                CMD  => \&_state,
                DESC => 'prints HostOS state information',
                HELP => ['prints HostOS state information'],
                DATA => {
                    state => {
                        chroot => 'state chroot',
                        root   => {
                            current => 'state root_current',
                            target  => 'state root_target',
                        },
                        release => 'state release',
                        user    => 'state user'
                    },
                    name  => 'machine self NAMES SHORT',
                    group => 'machine self GROUP',
                    nodes => 'machine nodes',
                }
            }
        }
    };

    return $struct;
}
1;

