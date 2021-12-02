#!/usr/bin/perl

# vbox guest additions/CIFS doesn't allow symlinks anymore, so for dev, the real Config::Plugins has to be added here
# this is edited out in the genesis cfgen Plugin. update the code there if this changes
use lib '../Libs', '.', '/data/local_config/genesis/op/gschnitzler/files/genesis';
use ModernStyle;
use Data::Dumper;
use Sys::Hostname;

use Core qw(load_core);

use PSI::Console qw(read_stdin);
use Config::Plugins qw(plugin_config);

$|++;    # print to stdout before newline

# genesis requires root
die 'ERROR: not root' unless ( getpwuid($<) eq 'root' );
##########################################################
my $core = load_core( { DEBUG => 0 } );

# load plugins
$core->{load}->(plugin_config);

my $hostname = hostname;
my $shell    = $core->{shell};
my $version  = $core->{VERSION};
my $chroot   = $core->{state}->{chroot};

# don't get interactive if commands are passed by command line.
# this also affects chroot macro resumes
exit $shell->( join( ' ', @ARGV ) ) if (@ARGV);

say "\n>> CORE (v", $version, ') Shell <<';
say 'Use CTRL+R to review history, CTRL+B and CTRL+F to edit';

my $prompt = $hostname;

while ( my $line = read_stdin( "$prompt # ", -style => 'bold yellow' ) ) {

    $shell->($line);

    if ( $chroot->() eq 'yes' ) {
        $prompt = "(chroot) $hostname";
    }
    else {
        $prompt = $hostname;
    }
}
