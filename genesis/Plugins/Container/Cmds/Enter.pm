package Plugins::Container::Cmds::Enter;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::RunCmds qw(run_cmd);

our @EXPORT_OK = qw(import_enter);

sub _enter_namespace ( $query, $container, @ ) {

    my $running = $query->('docker_container');
    my $pid;
    my $id;

    foreach my $k ( keys( $running->%* ) ) {

        my $rck = $running->{$k};
        $pid = $rck->{PID}            if ( $rck->{NAMES} eq $container );
        $id  = $rck->{'CONTAINER ID'} if ( $rck->{NAMES} eq $container );
    }

    if ( !$pid || !$id ) {
        say "Container $container not running";
        return 1;
    }

    #  run_cmd("nsenter --target $pid --mount --uts --ipc --net --pid");
    run_cmd("docker exec -it $id bash");

    return;
}

###############################################
# Frontend Functions

sub import_enter () {

    my $struct = {
        enter => {
            container => {
                CMD  => \&_enter_namespace,
                DESC => 'container shell access',
                HELP => [
                    'usage:', 'enter container <container>',
                    '',
                    'Requires Interactive genesis Shell.',
                    'Gives you a Shell inside a running Container. Much like docker attach',
                    'works with any running container'
                ],
                DATA => { docker_container => 'state docker_container', }
            }
        }
    };

    return $struct;
}
1;

