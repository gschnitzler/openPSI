#!/usr/bin/perl

use lib '/data/psi/Libs', '.';
use ModernStyle;
use Data::Dumper;

use Core qw(load_core);

use PSI::Console qw(read_stdin);
use Plugins qw(plugin_config);

$|++; # print to stdout before newline

######################################################
# cfgen is 2 things:
# - a build tool to compose modules and config into an executable
# - and sort of an ETL tool
# it Extracts various forms of configuration files (all the plugins dealing with the config directory),
# Transforms that into a format (all the plugins) that is understood by the modules it composes into genesis,
# which in turn is the Loader that does what is desired.
# while the concept of ETL is present, the Transformations happen where they make sense.
######################################################

my $debug = 1;
my $core  = load_core( { DEBUG => $debug } );    # load core
$core->{load}->( plugin_config($debug) );        # load plugins

# don't get interactive if commands are passed by command line.
# this also affects chroot macro resumes
if (@ARGV) {
    my $return = $core->{shell}->( join( ' ', @ARGV ) );
    exit $return;
}

say '';
say 'Use CTRL+R to review history, CTRL+B and CTRL+F to edit';
while ( my $line = read_stdin( 'cfgen # ', -style => 'bold green' ) ) {
    $core->{shell}->($line);
}

