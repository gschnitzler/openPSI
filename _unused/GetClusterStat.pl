#!/usr/bin/perl

use ModernStyle;


use Exporter qw(import);
use Data::Dumper;

# module should be in the mariadb_base image
use DBI;

####
my $username = $ARGV[0];
my $password = $ARGV[1];
my $hostname = $ARGV[2];
my $port     = $ARGV[3];
my $database = $ARGV[4];

#say "$username $password $hostname $port $database";
die "ERROR: unsufficient parameters" if ( !$username or !$password or !$hostname or !$port or !$database );

my $dsn = "DBI:mysql:database=$database;host=$hostname;port=$port";
my $dbh = DBI->connect( $dsn, $username, $password );

my $status = {};
my $sth    = $dbh->prepare("SHOW STATUS LIKE 'wsrep%'");
$sth->execute();
while ( my $ref = $sth->fetchrow_hashref() ) {
    $status->{ $ref->{Variable_name} } = $ref->{Value};
}
$sth->finish();
$dbh->disconnect();

my $filtered = {

    cluster_size        => $status->{wsrep_cluster_size},
    cluster_status      => $status->{wsrep_cluster_status},
    cluster_state_uuid  => $status->{wsrep_cluster_state_uuid},
    connected           => $status->{wsrep_connected},
    local_state_comment => $status->{wsrep_local_state_comment}

};

# security-wise, it would be better to sanitize the lsof output in genesis
# however, until there is a proper sensor handler, we just eval the output
say Dumper $filtered;

