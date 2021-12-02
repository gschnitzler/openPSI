package Core::Commands::Base;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Core::System::RunCmds qw(run_cmd);
use PSI::Parse::Templates qw(walk_structure walk_templates);
use PSI::Console qw(print_table);

# Export
our @EXPORT_OK = qw(import_hooks);
###############################################

# sub _get_template_pkg {

#     my @templates = @_;

#     print_table( "Looking for packages ", " ", ": " );

#     my @emerge = ();

#     my $filter_content = sub {
#         my ( $k, $v, $key_list ) = @_;

#         if ( $k eq "content" && ref $v eq "ARRAY" ) {

#             #say Dumper $v;
#             foreach my $line ($v->@*) {

#                 if ( $line =~ m/emerge\s+/ ) {

#                     # remove comments
#                     $line =~ s/#.*//;

#                     # removes RUN from Dockerfiles
#                     $line =~ s/^\s*RUN\s+//;

#                     # removes  stuff before emerge
#                     $line =~ s/.*emerge\s+//;

#                     # removes lines that start with emerge parameters
#                     $line =~ s/^-.*//;

#                     # lines my contain several packages... don't split them because they belong together
#                     # splitting them would pull in php and mysql into base
#                     # a bug to address with later refactor of the system scripts:
#                     # use flags are not taken into account
#                     push @emerge, $line if $line;
#                 }
#             }

#         }
#     };

#     foreach my $tree (@templates) {
#         walk_templates( $tree, [], $filter_content );
#     }

#     say "OK";

#     return (@emerge);
# }

sub _get_package_emerge {

    my @templates = @_;

    print_table( "Looking for packages ", " ", ": " );

    my @emerge = ();

    my $filter_content = sub {
        my ( $k, $v, $key_list ) = @_;

        if ( $k eq "emerge" ) {

            my $line = join( " ", $v->{CONTENT}->@* );
            $line =~ s/\#.*//x; # x requires \#
            $line =~ s/^\s*emerge\s+//x;
            push @emerge, $line if $line;
            return 1;
        }
        else {
            return 0;
        }
    };

    foreach my $tree (@templates) {
        walk_structure( $tree, [], $filter_content );
    }

    say "OK";
    return (@emerge);
}

sub _get_pkg_deps {

    my @pkgs      = @_;
    my $commons   = {};
    my $uniq_pkgs = {};

    foreach my $pkg (@pkgs) {

        print_table( "Reading Package deps ", "$pkg", ": " );

        _find_deps( $commons, _filter_doubles( $uniq_pkgs, $pkg ) );

        say "OK";

    }

    return ( $commons, $uniq_pkgs );

}

sub _sys_emerge {

    my $pkgs   = shift;
    my $params = shift;

    my @emerge = ();

    open( my $fh, "-|", "emerge -p $params $pkgs 2>&1 | grep '^\\['" )
        or die "could not open emerge command";

    my @input = <$fh>;
    close $fh;

    while ( my $line = shift @input ) {
        chomp $line;
        if ( $line =~ m/^\[[^\]]+\]\s+([^\[\s]+)/x ) {
            my $match = $1;
            push @emerge, $match if ($match);
        }

    }

    return @emerge;
}

sub _find_deps {

    my ( $commons, $pkgs ) = @_;

    my @emerge = _sys_emerge( $pkgs, "--columns --onlydeps" );

    foreach my $em (@emerge) {

        if ( exists( $commons->{$em} ) ) {
            $commons->{$em} = $commons->{$em} + 1;
        }
        else {
            $commons->{$em} = 1;
        }
    }
    return;

}

sub _filter_doubles {

    my ( $uniq, $pkg ) = @_;

    my @single = split( /\s+/x, $pkg );
    my @filtered = ();
    foreach my $single_pkg (@single) {

        unless ( exists( $uniq->{$single_pkg} ) ) {

            push @filtered, $single_pkg;
            $uniq->{$single_pkg} = "";
        }
    }

    return ( join( ' ', @filtered ) );
}

###############################################
# Frontend Functions

sub base {

    my ( $core, $def ) = @_;
    my $state = $def->{state};

    # forbidded packages
    my @masked = ( "dev-lang/php", "virtual/mysql", "dev-db/mariadb", );

    #my ( $commons, $uniq_pkgs ) = _get_pkg_deps( _get_template_pkg( $def->{host}->{build}->{HostOS}, $def->{docker}->{IMAGES} ) );
    my ( $commons, $uniq_pkgs ) = _get_pkg_deps( _get_package_emerge( $def->{host}->{build}->{HostOS}, $def->{docker}->{IMAGES} ) );
    say "\nFound ", scalar keys $uniq_pkgs->%*, " unique packages with ", scalar keys $commons->%*, " deps.\n";

    # never use each
    #while ( my ( $k, $v ) = each $commons->%* ) {
    foreach my $k (keys $commons->%*){

        my $v = $commons->{$k};
        
        print_table( "Package", "$k", ": " );
        if ( $v <= 1 ) {

            say "dropped (only one parent)";
            delete $commons->{$k};
            next;
        }
        if ( exists( $uniq_pkgs->{$k} ) ) {

            say "dropped (is a parent)";
            delete $commons->{$k};
            next;
        }

        print "calculating deps: ";

        my @deps = _sys_emerge( $k, "--columns" );

        my @hits = ();
        foreach my $em (@deps) {

            foreach my $mask (@masked) {

                if ( $em =~ /$mask/x ) {
                    delete $commons->{$k};
                    push @hits, $em;
                    last;
                }
            }
        }
        if ( scalar @hits ) {
            say "dropped (masked dep: ", join( " ", @hits ), ")";
        }
        else {
            say "OK";
        }
    }

    print_table( "Installable deps found", " ", ": " );
    say scalar keys $commons->%*;
    say "";
    say join( "\n", keys $commons->%* );
    my $allpkg = join( " ", keys $commons->%* );

    run_cmd("emerge $allpkg") if $allpkg;
    return;
}

sub import_hooks {

    my $cmds = { base => \&base, };
    my $help = {
        base => [
            "usage:",
            "base",
            "finds packages to be emerged in HostOS and Dockerfiles,",
            "then evaluate common packages and installs only them.",
            "used to reduce compile overhead for container building"
        ]
    };
    my $shorthelp = { base => "finds and install common packages" };

    my $data_def = {
        state  => "",
        docker => { IMAGES => "" },
        host   => { build => { HostOS => "" } }

    };
    return ( $data_def, $cmds, $help, $shorthelp );

}
1;

