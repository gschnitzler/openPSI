#!/usr/bin/perl
########################
use File::Basename;    # used for dirname
use Cwd qw(chdir);     # this also sets $ENV{PWD} on chdir
chdir dirname $0;      # so relative paths in config keep working when called with absolute paths
########################

use lib '.', '/data/config', '/data/config/am', '/data/psi/Libs';
use ModernStyle;

use PSI::RunCmds qw(run_system);
use IO::Config::Check qw(file_exists);

use Config::Throttler qw(throttler_config);

$|++;                  # autoflush (logging breaks otherwise)
#########################

my $config          = throttler_config();
my $manual_throttle = $config->{global}->{manual_throttle};

if ( file_exists $manual_throttle ) {
    print 'Lifting manual throttle: ';
    local ( $!, $? );
    unlink $manual_throttle or die "ERROR: could not delete $manual_throttle";
    say 'OK';
}
else {
    print 'Setting manual throttle: ';
    run_system "touch $manual_throttle";
    say 'OK';
}
exit 0;
