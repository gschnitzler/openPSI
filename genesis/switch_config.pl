#!/usr/bin/perl -w
#
#
use lib '/data/psi/Libs';
use ModernStyle;
use PSI::RunCmds qw(run_cmd);

my $local_config   = '/data/local_config/genesis';
my $genesis_config = '/data/psi/genesis/Config';

my ( $cluster, $machine ) = split( /\//, $ARGV[0] );
die "ERROR: invalid argument" if ( !$cluster || !$machine );

my $config_path = "$local_config/$cluster/$machine/files/genesis/Config";
die "ERROR: no such config" if ( !-e $config_path || !-d $config_path );

run_cmd( "rm -f $genesis_config", "ln -s $config_path $genesis_config" );

