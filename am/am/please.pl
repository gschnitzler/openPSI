#!/usr/bin/perl
########################
use File::Basename;    # used for dirname
use Cwd qw(chdir);     # this also sets $ENV{PWD} on chdir
chdir dirname $0;      # so relative paths in config keep working when called with absolute paths
########################

# do not add genesis Libs path here, as the lacking permissions in production will prevent perl to load *any* module. even Core.
use lib '/usr/lib64/perl5/am', '/usr/lib64/perl5/Libs';    # am in production
use lib '.';                                               # am in dev. when working on Libs, replace the above Libs folder with a symlink to genesis Libs.
use ModernStyle;

use AM::DIO qw(am_dio_client am_dio_input);
use Config::DIO qw (am_dio_config);

$|++;                                                      # autoflush (logging breaks otherwise)
#####################

$SIG{INT} = sub {
    print time(), ": DON'T BREAK OPERATION. SIGNAL IGNORED";
    return;
};

my $config      = am_dio_config();
my $socket_path = $config->{socket};
my $dio_client  = am_dio_client($socket_path);
my $cmd         = am_dio_input @ARGV;
$dio_client->( 'WRITE', 'GENESIS', $cmd );
exit 0;

