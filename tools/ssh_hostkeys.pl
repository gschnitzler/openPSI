#!/usr/bin/perl

use lib '/data/psi/Libs';
use lib '/data/psi/cfgen';
use ModernStyle;
use Data::Dumper;

use IO::Config::Read qw(read_config_single load_config);

my $config_path = "/data/psi/config/Cluster/";
my $cluster     = load_config( read_config_single( 0, $config_path ) );
my @machines    = ();

foreach my $cluster_name ( keys $cluster->%* ) {

    my $machine_path = join( '/', $config_path, $cluster_name );
    push @machines, load_config( read_config_single( 0, $machine_path ) );
}

foreach my $machine_hash (@machines) {

    foreach my $key ( keys( $machine_hash->%* ) ) {

        my $machine = $machine_hash->{$key};
        my $name    = $machine->{NAMES}->{SHORT};
        my $group   = $machine->{GROUP};

        die 'ERROR: mixed names' if ( $key ne $name );

        my $file_rsa_key="ssh.host.$group.$name.rsa.key.priv";
        my $file_rsa_pub="ssh.host.$group.$name.rsa.key.pub";
        my $file_ed2_key="ssh.host.$group.$name.ed25519.key.priv";
        my $file_ed2_pub="ssh.host.$group.$name.ed25519.key.pub";

        system "rm -f $file_rsa_key";
        system "rm -f $file_ed2_key";

        system "ssh-keygen -N '' -t rsa -b 4096 -f $file_rsa_key -C '$group/$name'";
        system "ssh-keygen -N '' -t ed25519 -f $file_ed2_key -C '$group/$name'";

        system "mv $file_rsa_key.pub $file_rsa_pub";
        system "mv $file_ed2_key.pub $file_ed2_pub";

    }

}

