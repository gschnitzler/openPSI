package Plugins::HostOS::Cmds::PackageVersion;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table print_line);
use PSI::Parse::Packages qw(read_system_packages read_pkgversion compare_pkgversion);
use PSI::Parse::File qw(write_file);

our @EXPORT_OK = qw(import_packageversion);

#######################################################

sub _save_packageversion ( $query, @ ) {

    my $pkgversion_f = $query->('pkgversion');
    print_table( 'Saving', $pkgversion_f, ': ' );
    write_file(
        {
            PATH    => $pkgversion_f,
            CONTENT => [ join( "\n", read_system_packages(), '' ) ],
        }
    );

    say 'OK';
    return 0;
}

sub _compare_systemversion ( $query, @ ) {

    my $pkgversion_f    = $query->('pkgversion');
    my $mount           = $query->('mount');
    my $system_packages = read_pkgversion($pkgversion_f);
    my $new_packages    = read_pkgversion("$mount$pkgversion_f");

    print_line('');    # empty string needed, otherwise signatures fail
    compare_pkgversion( $system_packages, $new_packages );

    return;
}

sub _compare_packageversion ( $query, @ ) {

    my $pkgversion_f    = $query->('pkgversion');
    my $new_packages    = {};
    my $system_packages = read_pkgversion($pkgversion_f);

    say 'enter version list. Type \'EOF\' on its own line when finished';

    # <> only works when genesis is called in shell mode.
    # if genesis is called with command line parameters, then <> is not STDIN,
    # so don't use <>
    while ( my $line = <STDIN> ) {    ## no critic

        chomp $line;
        last if ( $line eq 'EOF' );
        $line =~ s/^\s*//x;
        $line =~ s/\s*$//x;

        my ( $name, $version, $mask, @useflags ) = split( ' ', $line );

        next if ( !$name || !$version || !$mask );    # use flags might be empty

        if ( exists( $new_packages->{$name} ) ) {
            die "ERROR: found duplicate '$name' in input";
        }
        $new_packages->{$name} = { version => $version, mask => $mask, useflags => join( ' ', @useflags ) };
    }

    print_line('');                                   # empty string needed, otherwise signatures fail
    compare_pkgversion( $system_packages, $new_packages );

    return;
}

###########################################

sub import_packageversion () {

    my $struct = {
        save => {
            package => {
                version => {
                    CMD  => \&_save_packageversion,
                    DESC => 'write gentoo package version information to disk',
                    HELP => ['write gentoo package version information to disk'],
                    DATA => { pkgversion => 'paths hostos PKGVERSION', }
                }
            }
        },
        compare => {
            package => {
                version => {
                    CMD  => \&_compare_packageversion,
                    DESC => 'compare package version information from STDIN with current state',
                    HELP => ['compare package version information from STDIN with current state'],
                    DATA => { pkgversion => 'paths hostos PKGVERSION', }
                }
            },
            system => {
                version => {
                    CMD  => \&_compare_systemversion,
                    DESC => 'compare package version information from mount with current state',
                    HELP => ['compare package version information from mount with current state'],
                    DATA => { pkgversion => 'paths hostos PKGVERSION', mount => 'paths hostos MOUNT' }
                }
            }
        }
    };

    return $struct;
}
1;
