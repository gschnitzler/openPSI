#!/usr/bin/perl
########################
use File::Basename;    # used for dirname
use Cwd qw(chdir);     # this also sets $ENV{PWD} on chdir
chdir dirname $0;      # so relative paths in config keep working when called with absolute paths
########################

use lib '.', '/data/config', '/data/config/am', '/data/psi/Libs';
use ModernStyle;

use AM::Forker qw(am_forker);
use Config::Forker qw(am_forker_config);

$|++; # autoflush (logging breaks otherwise)
################################

my $server = am_forker( am_forker_config() );
exit $server->();
