#!/usr/bin/perl
########################
use File::Basename;    # used for dirname
use Cwd qw(chdir);     # this also sets $ENV{PWD} on chdir
chdir dirname $0;      # so relative paths in config keep working when called with absolute paths
########################

use lib '.', '/data/config', '/data/config/am', '/data/psi/Libs';
use ModernStyle;

use AM::Inotify qw(am_inotify);
use Config::Inotify qw(am_inotify_config);

$|++; # autoflush (logging breaks otherwise)
#########################

my $server = am_inotify( am_inotify_config() );
exit $server->();
