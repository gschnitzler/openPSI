package Plugins::Container::Docker::Container::Stop;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(create_container_stop_script);

#########################################################

sub _get_id ( $running_container, $container_name ) {
    foreach my $key ( keys $running_container->%* ) {
        my $running = $running_container->{$key};
        return $running->{'CONTAINER ID'} if ( $running->{NAMES} eq $container_name );
    }
    return;
}

#########################################################

sub create_container_stop_script ( $container_name, $data_path, $running_container ) {

    my $id = _get_id( $running_container, $container_name );

    return [] unless ($id);

    my @docker_stop = (
        "docker stop $id > /dev/null 2>&1",
        "docker wait $id > /dev/null 2>&1",    # docker rm -f would SIGKILL. which is bad, hence the stop, wait, rm.
        "docker rm -f $id > /dev/null 2>&1",
        "umount -lf $data_path > /dev/null 2>&1 || true",
    );

    return \@docker_stop;
}

1;
