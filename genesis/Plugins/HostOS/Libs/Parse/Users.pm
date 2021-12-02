package Plugins::HostOS::Libs::Parse::Users;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use PSI::Parse::File qw(parse_file write_file);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(read_users write_users);

Readonly my $PASSWD_PW    => 0;
Readonly my $PASSWD_UID   => 1;
Readonly my $PASSWD_GID   => 2;
Readonly my $PASSWD_DESC  => 3;
Readonly my $PASSWD_HOME  => 4;
Readonly my $PASSWD_SHELL => 5;

Readonly my $GROUP_PW    => 0;
Readonly my $GROUP_GID   => 1;
Readonly my $GROUP_USERS => 2;

Readonly my $SHADOW_PW          => 0;
Readonly my $SHADOW_LASTCHANGED => 1;
Readonly my $SHADOW_MIN         => 2;
Readonly my $SHADOW_MAX         => 3;
Readonly my $SHADOW_WARN        => 4;
Readonly my $SHADOW_INACTIVE    => 5;
Readonly my $SHADOW_EXPIRE      => 6;
Readonly my $SHADOW_UNKNOWN     => 7;    # seems gentoos shadow has one more field I don't know about

my $routines = {
    passwd => {
        path => '/etc/passwd',
        read => sub ($entry) {
            push $entry->@*, '' for ( $PASSWD_PW .. $PASSWD_SHELL );
            return (
                {
                    PW    => $entry->[$PASSWD_PW],
                    UID   => $entry->[$PASSWD_UID],
                    GID   => $entry->[$PASSWD_GID],
                    DESC  => $entry->[$PASSWD_DESC],
                    HOME  => $entry->[$PASSWD_HOME],
                    SHELL => $entry->[$PASSWD_SHELL]
                }
            );
        },
        write => sub ( $u, $e ) {
            return ( join( ':', $u, $e->{PW}, $e->{UID}, $e->{GID}, $e->{DESC}, $e->{HOME}, $e->{SHELL} ) );
        }
    },
    group => {
        path => '/etc/group',
        read => sub ($entry) {
            push $entry->@*, '' for ( $GROUP_PW .. $GROUP_USERS );
            return (
                {
                    PW    => $entry->[$GROUP_PW],
                    GID   => $entry->[$GROUP_GID],
                    USERS => $entry->[$GROUP_USERS],
                }
            );
        },
        write => sub ( $g, $e ) {
            return ( join( ':', $g, $e->{PW}, $e->{GID}, $e->{USERS} ) );
        }
    },
    shadow => {
        path => '/etc/shadow',
        read => sub ($entry) {

            # seems gentoos shadow has one more field I don't know about
            # as I don't care about shadow contents anyway, just add it and be done with it
            push $entry->@*, '' for ( $SHADOW_PW .. $SHADOW_UNKNOWN );
            return (
                {
                    PW          => $entry->[$SHADOW_PW],
                    LASTCHANGED => $entry->[$SHADOW_LASTCHANGED],
                    MIN         => $entry->[$SHADOW_MIN],
                    MAX         => $entry->[$SHADOW_MAX],
                    WARN        => $entry->[$SHADOW_WARN],
                    INACTIVE    => $entry->[$SHADOW_INACTIVE],
                    EXPIRE      => $entry->[$SHADOW_EXPIRE],
                }
            );
        },
        write => sub ( $u, $e ) {

            # added an empty field
            return ( join( ':', $u, $e->{PW}, $e->{LASTCHANGED}, $e->{MIN}, $e->{MAX}, $e->{WARN}, $e->{INACTIVE}, $e->{EXPIRE}, '' ) );
        }
    }
};

sub _struct_list ( $struct, $heap, $flush_heap, $line ) {

    my @s_line = split( /:/, $line );
    my $entry  = shift @s_line;

    $struct->{$entry} = \@s_line;
    return;
}

##############################################################

sub write_users ($struct) {

    #say Dumper $struct;
    foreach my $file ( keys( $routines->%* ) ) {

        my $file_path = $routines->{$file}->{path};
        print_table( 'Writing', $file_path, ': ' );
        die 'ERROR: incomplete data' unless ( $struct->{$file} );

        my $file_data    = $struct->{$file};
        my @file_content = ();

        foreach my $entry ( keys( $file_data->%* ) ) {

            my $line = $routines->{$file}->{write}->( $entry, $file_data->{$entry} );
            push @file_content, join( '', $line, "\n" );
        }

        #      say @file_content;
        write_file(
            {
                PATH    => $file_path,
                CONTENT => \@file_content,
            }
        );
        say 'OK';
    }
    return;
}

sub read_users () {

    my $all_files = {};
    foreach my $file ( keys( $routines->%* ) ) {

        my $file_path = $routines->{$file}->{path};
        print_table( 'Reading', $file_path, ': ' );
        my $struct = parse_file( $file_path, \&_struct_list, sub (@) { } );

        foreach my $entry ( keys( $struct->%* ) ) {
            $struct->{$entry} = $routines->{$file}->{read}->( $struct->{$entry} );
        }

        $all_files->{$file} = $struct;
        say 'OK';
    }
    return ($all_files);
}

1;
