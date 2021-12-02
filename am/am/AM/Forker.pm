package AM::Forker;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Child;

use InVivo qw(kexists);
use AM::STDout qw(print_stdout);
use AM::Queue qw(am_queue);
use AM::Socket qw(base_protocol write_socket);
use AM::Socket::Server qw(server);
use AM::Socket::Client qw(client);

our @EXPORT_OK = qw(am_forker);

#############################
# global used by functions below
my $queue = am_queue();
#############################

sub _get_filepath($file_path) {

    my @p    = split /\//, $file_path;
    my $file = pop @p;
    my $path = join '/', @p;
    return $path, $file;
}

sub _receive ( $handlers, $socket_path, $max_running, $type, $file_path, $event, @args ) {

    my ( $path, $file ) = _get_filepath $file_path;
    my $handler_args = $handlers->{$path}->{$event}->{args};
    my $handler =
      kexists($handlers, $path, $event, 'handler')
      ? $handlers->{$path}->{$event}->{handler}
      : $handlers->{'*'}->{handler};    # use the default handler or a designated handler if any
    my $task = Child->new(              # create a worker process to spawn later
        sub ( $parent, @ ) {
            local $SIG{CHLD} = 'DEFAULT';    # let childs have their own handler.
            my $client    = client $socket_path, \&_client_protocol;
            my $exit_code = $handler->( $client, $path, $file, $event, $handler_args, @args );
            $exit_code = $exit_code ? $exit_code : 0;
            $client->( 'WRITE', 'QUEUE', 'FINISHED', "$path/$file", $event, $exit_code );    # remove task from running queue
            $client->('CLOSE');                                                              # close the client fh
            return $exit_code;
        }
    );

    print_stdout $queue->{$type}->( $task, $path, $file, $event, @args ) if exists $queue->{$type};    # unrecognized types are just dropped here
    print_stdout $queue->{SHIFT}->( $socket_path, $max_running );                                      # fills up running with jobs from queue

    return;
}

sub _server_protocol ( $socket, @load_args ) {
    return {
        base_protocol(),
        QUEUE => {

            # RECEIVE return values are fed into SEND in server context.
            # we do not want to answer on QUEUE receive. so there is a client_protocol
            SEND    => sub(@)     { },
            RECEIVE => sub(@args) { _receive @load_args, @args },
        },
    };
}

sub _client_protocol ( $socket ) {
    return {
        base_protocol(),
        QUEUE => {
            SEND => sub(@args) {
                write_socket $socket->$*, 'QUEUE', @args;
                return;
            },
            RECEIVE => sub(@) { },
        },
    };
}

################################

sub am_forker($config) {

    my $socket_path = $config->{global}->{socket_path};
    my $max_running = $config->{global}->{max_jobs};
    my $handlers    = $config->{paths};

    die 'ERROR: Incomplete config' if ( !$socket_path || !$max_running || !$handlers );
    return sub(@args) {

        my $old_handler = $SIG{CHLD};    # save handler
        $SIG{CHLD} = 'IGNORE';           # set handler to autoreap
        my $server = server( $socket_path, sub($s) { return _server_protocol( $s, $handlers, $socket_path, $max_running ); } );
        my $ec     = $server->(@args);
        $SIG{CHLD} = $old_handler;       # restore old handler
        return $ec;
    };
}

1;
