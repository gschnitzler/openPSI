package Plugins::Container::Cmds::Manage;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Time::HiRes qw(sleep);
use Readonly;

use InVivo qw(kexists);
use PSI::RunCmds qw(run_cmd run_system run_open);
use PSI::Console qw(print_table);
use PSI::Parse::Dir qw(get_directory_tree get_directory_list);
use Process::Manager qw(task_manager);
use Process::Message qw(get_msg put_msg);
use IO::Templates::Meta::Apply qw(apply_meta);
use IO::Templates::Meta::Write qw(meta_chownmod);

use Plugins::Container::Docker::Network::Start qw(create_network_start_script);
use Plugins::Container::Docker::Network::Stop qw(create_network_stop_script);
use Plugins::Container::Docker::Container::Start qw(create_container_start_script);
use Plugins::Container::Docker::Container::Stop qw(create_container_stop_script);
use Plugins::Container::Docker::Container qw(solve_order get_containers);

Readonly my $SLEEP_INTERVAL => 0.2;

our @EXPORT_OK = qw(import_manage);

###########################################

sub _get_core_count() {

    # does not work. we rely on relaying messages, so all workers need to be started
    #my ( $core_count, @rest ) = run_open 'nproc';
    my $core_count = 1000;
    return $core_count;
}

sub _wait_finished ( $data, $container_name ) {

    return unless kexists( $data, 'config', 'WAIT_FINISHED' );

    my $waitfor = $data->{config}->{WAIT_FINISHED};

    print_table( 'Waiting on', $container_name, ': ' );
    say scalar keys $waitfor->%*;
    
    local ( $!, $? );

  GETOUT: while (1) {

        # the following 3 lines are from readline doc, and replaced
        # foreach my $msg ( get_msg( readline( STDIN ) ) ) {    ## no critic
        # which started to emit 'Resource temporarily unavailable' (EAGAIN) in $! after years of no issues.
        # ... and on the next machine it threw out illegal seeks. did not even bother looking. as long as there is no error, suppress it.
        #while ( !eof(STDIN) ) {
        #    defined( $_ = readline STDIN ) or die "readline failed: $!";
        #    my $msg = get_msg($_);
        # and changed back again as it suddenly stopped working
        foreach my $msg ( get_msg( readline(STDIN) ) ) {    ## no critic
            delete $waitfor->{ $msg->{from} } if ( $msg->{msg} eq 'FINISHED' );

            #say "$container_name waitfor to go:", scalar keys $waitfor->%*;
            last GETOUT if scalar keys $waitfor->%* == 0;
        }
        sleep $SLEEP_INTERVAL;
    }
    return;
}

sub _tell_finished ( $data, $container_name ) {

    return unless kexists( $data, 'config', 'TELL_FINISHED' );

    my $tell_finished = $data->{config}->{TELL_FINISHED};

    #print_table( 'Telling finished', $container_name, ': ' );
    #say join( ' ', keys $start_after->%* );

    foreach my $e ( keys( $tell_finished->%* ) ) {
        put_msg {
            from => $container_name,
            to   => $e,
            msg  => 'FINISHED',
        };
    }
    return;
}

sub _get_pid ( $running_after_start, $container_name ) {

    foreach my $k ( keys( $running_after_start->%* ) ) {

        my $rck = $running_after_start->{$k};
        return $rck->{PID} if ( $rck->{NAMES} eq $container_name );
    }
    return;
}

sub _do_container_start ( $query, $data ) {

    # Forks::Super does not clear this, so invoking anything that checks that will break ( like run_cmd)
    local $? = 0;
    local $! = 0;
    my $container_name         = $data->{config}->{NAME};
    my $data_path              = $data->{config}->{DOCKER}->{PATHS}->{DATA};
    my $pdata_path             = $data->{config}->{DOCKER}->{PATHS}->{PERSISTENT};
    my @create_directories     = $data->{docker}->{create_dirs}->@*;
    my @create_map_directories = $data->{docker}->{create_map_dirs}->@*;
    my @mount_data             = $data->{docker}->{mount_data}->@*;
    my $docker_run_string      = $data->{docker}->{docker_run};
    my $running_container      = $data->{docker}->{running_container};
    my @networking_script      = $data->{network}->@*;
    my $init_log               = join '/', $pdata_path, 'init.log';

    print_table( 'Starting container ', $container_name, ': ' );

    foreach my $k ( keys $running_container->%* ) {

        if ( $running_container->{$k}->{NAMES} eq $container_name ) {
            say 'NO (already running)';
            return;
        }
    }

    run_cmd( @create_directories, @create_map_directories );    # create dirs if they don't exist

    # when the data dir is empty, and a data image exists, mount it (this behaviour is used by 'staging')
    # the data directory was previously unmounted by @create_directories (because it needed to for permissions)
    my $dircontent = get_directory_list($data_path);

    run_cmd(@mount_data) if ( scalar keys $dircontent->%* == 0 );
    run_cmd($docker_run_string);

    my $pid = _get_pid( $query->('docker_container'), $container_name );
    die 'ERROR: could not get PID' unless ($pid);

    say 'OK';

    print_table( 'Linking Network', $container_name, ': ' );

    s/§pid/$pid/g for (@networking_script);    # replace §pid with the actual pid of the container

    run_cmd(@networking_script);

    say 'OK';

    # run this before permission updates.
    # init files may setup folders in pdata etc
    if ( kexists( $data, 'config', 'PRE_INIT' ) ) {
        foreach my $script_name ( keys $data->{config}->{PRE_INIT}->%* ) {
            print_table( 'Running pre-init', "$container_name:$script_name", ': ' );
            my $script = $data->{config}->{PRE_INIT}->{$script_name}->{CONTENT};
            for my $line ( $script->@* ) {
                next if $line =~ /^\s*#/;
                next if $line =~ /^\s*$/;

             # devs might find it useful to have access to logs emitted by init scripts. op work is speed up by having access to the log directly on the machine
             # with the -s switch, logger emits its messages on stderr, which we then redirect into a local file for that purpose.
                run_system "docker exec $container_name $line 2>&1 | logger -e -s -t '$container_name init_$script_name' 2>>$init_log";
            }
            say 'OK';
        }
    }

    # apply permissions (from outside the container, otherwise a script would need to be injected)
    if ( kexists( $data, 'config', 'OVERLAY_PERMISSIONS' ) ) {
        my $cc = $data->{config};
        foreach my $overlay_key ( keys $cc->{OVERLAY_PERMISSIONS}->%* ) {
            my $overlay   = $cc->{OVERLAY_PERMISSIONS}->{$overlay_key};
            my $host_path = $cc->{DOCKER}->{PATHS}->{$overlay_key};
            print_table( 'Applying Permissions', "$container_name:$overlay_key", ': ' );
            meta_chownmod( apply_meta( get_directory_tree($host_path), $overlay ), "$host_path/" );
            say 'OK';
        }
    }

    run_system "docker exec -d $container_name touch /init_complete";    # set init_complete flag for init.pl

    return;
}

sub _do_container_stop($data) {

    # Forks::Super does not clear this, so invoking anything that checks that will break ( like run_cmd)
    local $? = 0;
    local $! = 0;
    my @network_stop   = $data->{network}->@*;
    my @docker_stop    = $data->{docker}->@*;
    my $container_name = $data->{config}->{NAME};

    _wait_finished( $data, $container_name );

    print_table( 'Removing Container ', $container_name, ': ' );

    if ( scalar @docker_stop > 1 ) {
        run_cmd(@docker_stop);
        say 'OK';
    }
    else {
        say 'NO (not running)';
    }

    print_table( 'Unlinking Network', $container_name, ': ' );
    run_cmd(@network_stop);
    say 'OK';

    _tell_finished( $data, $container_name );
    return;
}

sub _start_container ( $query, @args ) {    ## no critic

    print_table( 'Preparing Container Start', '', ': ' );

    my $config            = $query->('config');
    my $net_state         = $query->('network');
    my $docker_images     = $query->('image_list');
    my $running_container = $query->('docker_container');
    my $images            = $query->('images');
    my @tostart           = ();

    # get an array of all the config entries of registered containers for this machine,
    # and create an array of structures containing that configuration and other data needed for runtime
    # the structure is made for the task_manager

    foreach my $e ( get_containers( $config, @args ) ) {

        push @tostart, {
            DATA => {
                config  => $e,
                network => create_network_start_script( $e, $net_state->{PUBLIC}, $net_state->{INTERN} ),
                docker  => create_container_start_script( $e, $docker_images, $images, $running_container ),
            },
            TASK  => sub(@) { _do_container_start( $query, @_ ) },
            QUEUE => {},

            # this is tricky. on container start stuff like image unpacking happens.
            # also, pre-init tasks happen here, that might take some time.
            # for the sake of not deadlocking during boot, lets set it to 10m.
            # with 3 deps, this might still add up to a very high timeout
            TIMEOUT => 600,
        };
    }

    my ( $start_tree, @unsolved ) = solve_order( \@tostart, [ 'WAIT_FINISHED', 'TELL_FINISHED' ] );
    say 'OK';

    print_table( 'WARNING: unsolved dependency', $_->[0], ": $_->[1]\n" ) foreach (@unsolved);

    my $debug = 0;
    task_manager( $debug, $start_tree, _get_core_count );
    return;
}

sub _stop_container ( $query, @args ) {

    print_table( 'Preparing Container Stop', '', ': ' );

    my $config            = $query->('config');
    my $running_container = $query->('docker_container');
    my @tostop            = ();

    foreach my $e ( get_containers( $config, @args ) ) {

        push @tostop, {
            DATA => {
                config  => $e,
                network => create_network_stop_script( $e->{NAME}, $e->{NETWORK}->{INTERFACE} ),
                docker  => create_container_stop_script( $e->{NAME}, $e->{DOCKER}->{PATHS}->{DATA}, $running_container ),
            },
            TASK    => \&_do_container_stop,
            QUEUE   => {},
            TIMEOUT => 200,                    # should be plenty to stop all container
        };
    }

    my ( $stop_tree, @unsolved ) = solve_order( \@tostop, [ 'TELL_FINISHED', 'WAIT_FINISHED' ] );
    say 'OK';

    print_table( 'WARNING: unsolved dependency', $_->[0], ": $_->[1]\n" ) foreach (@unsolved);

    my $debug = 0;
    task_manager( $debug, $stop_tree, _get_core_count );
    return;
}

###############################################
# Frontend Functions

sub import_manage () {

    my %start = (
        config           => 'container',
        docker_container => 'state docker_container',
        image_list       => 'state docker_image_list',
        network          => 'state network',
        images           => 'state images'
    );

    my $struct = {
        start => {
            container => {
                CMD  => \&_start_container,
                DESC => 'starts a container',
                HELP => [
                    'usage:',
                    'start container <container> [args]: starts <container>',
                    'start container: starts all containers',
                    '[args] are passed to docker run (ie /bin/bash)',
                    'note that you can only pass [args] to a single container'
                ],
                DATA => {%start}
            }
        },
        stop => {
            container => {
                CMD  => \&_stop_container,
                DESC => 'stops a container',
                HELP => [ 'usage:', 'stop container <container>: stops <container>', 'stop container: stops all containers' ],
                DATA => {
                    config           => 'container',
                    docker_container => 'state docker_container',
                }
            }
        },

        restart => {
            container => {
                CMD => sub (@arg) {

                    # if you get the glorious idea to chain the containers start and stop tree in order to speed up things, be warned:
                    # the system state $query is evaluated before process launch. if you wanted to wait on a container stop to start,
                    # the $query must be moved into the processes. This will be the first step into a world of pain.
                    # Please don't bother. its fast and hard to debug enough as it is.
                    _stop_container(@arg);
                    _start_container(@arg);
                },
                DESC => 'restarts a container',
                HELP => [ 'usage:', 'restart container <container>: restarts <container>', 'restart container: restarts all containers' ],
                DATA => {%start}
            }
        }
    };

    return $struct;
}
1;

