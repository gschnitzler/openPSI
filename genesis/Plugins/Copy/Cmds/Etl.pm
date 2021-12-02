package Plugins::Copy::Cmds::Etl;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::RunCmds qw(run_system);
use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw(import_etl);

#############

sub copy_etl ( $query, @args ) {

    my $container = $query->('container');

    my ( $container_arg, undef, undef, $company_id, undef, $destination_dir ) = @args;

    die 'ERROR: no container name given'        unless $container_arg;
    die 'ERROR: no company id given'            unless $company_id;
    die 'ERROR: no destination directory given' unless $destination_dir;

    my ( $container_name, $stage ) = split( /_/, $container_arg );

    die 'ERROR: invalid container name' if ( !$container_name || !$stage );
    die "ERROR: container $container_arg does not exist" unless kexists( $container, $container_name, $stage );

    my $requested_container = $container->{$container_name}->{$stage};
    my $source_path         = $requested_container->{config}->{DOCKER}->{PATHS}->{PERSISTENT};

    $source_path = join( '/', $source_path, "etl/staging/$company_id" );

    die "ERROR: company id $company_id does not exist"                 unless ( dir_exists $source_path );
    die 'ERROR: destination directory is not an absolute path'         unless ( $destination_dir =~ /^\// );
    die "ERROR: destination directory $destination_dir does not exist" unless ( dir_exists $destination_dir );

    run_system "rm -rf $destination_dir/$company_id";
    run_system "cp -Rfp $source_path $destination_dir";
    run_system "chmod -R o+rwx $destination_dir/$company_id";
    return;

}

################
sub import_etl () {

    my $struct = {};

    $struct->{copy}->{etl}->{log}->{of} = {
        CMD  => \&copy_etl,
        DESC => 'copies logs from ETL',
        HELP => [ 'usage: copy etl log of <container_name> with id <company_id> to <dir>', '<dir> must be an absolute path' ],
        DATA => { container => 'container' }
    };

    return $struct;
}

1;

