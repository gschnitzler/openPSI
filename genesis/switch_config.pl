#!/usr/bin/perl -w
#
#
use lib '/data/psi/Libs';
use ModernStyle;
use PSI::RunCmds qw(run_cmd);
my $use_config = $ARGV[0];

die 'ERROR: need a valid argument' unless ($use_config);

my ( $cluster, $machine ) = split( /\//, $use_config );
die "ERROR: invalid argument: $use_config" if ( !$cluster || !$machine );

my $config_path = "/data/local_config/genesis/$cluster/$machine/genesis/Config";
die "ERROR: no such config $use_config" if ( !-e $config_path || !-d $config_path );

run_cmd( 'rm ./Config', "ln -s $config_path ./Config" );

