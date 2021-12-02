package AM::DIO;

use ModernStyle;
use Exporter qw(import);

use PSI::RunCmds qw(run_open);

use AM::Socket qw(base_protocol write_socket);
use AM::Socket::Server qw(server);
use AM::Socket::Client qw(client);

our @EXPORT_OK = qw(am_dio_server am_dio_client am_dio_input);

#######################

sub am_dio_input(@args) {
    my @allowed_commands = (
        qr/^test\ .*/,
        qr/^restart\ container\ .*/,
        qr/^stage\ .*/,
        qr/^start container\ .*/,
        qr/^stop container\ .*/,
        qr/^copy etl log of\ .*/,
        qr/^restart production container\ .*/,
    );

    my $line = join( ' ', @args );
    $line =~ s/[^a-zA-Z0-9§ \.\-_\/]//g;    # only allow characters that could be used as genesis commands

    for my $allowed (@allowed_commands) {
        return $line if ( $line =~ /$allowed/ );
    }
    return 'FAILED';
}

sub _server_protocol ( $socket ) {
    return {
        base_protocol(),
        STDOUT => {
            SEND    => sub(@) { },
            RECEIVE => sub(@) { }
        },
        FAILED => {
            SEND => sub(@) {
                write_socket $socket->$*, 'FAILED';
                return;
            },
            RECEIVE => sub(@) { }
        },
        SUCCESS => {
            SEND => sub(@) {
                write_socket $socket->$*, 'SUCCESS';
                return;
            },
            RECEIVE => sub(@) { }
        },
        GENESIS => {
            SEND => sub (@args) {

                my $error = 0;

                if ( $args[0] eq 'DISABLED' ) {
                    write_socket $socket->$*, 'STDOUT', 'ERROR: command unavailable.';
                    return 1;
                }
                my $open_error = sub ( $cmd, $msg, $ec ) {    # permissions, or file got deleted before this handler is run.
                    write_socket $socket->$*, 'STDOUT', "ERROR: opening MSG:'$msg' EC:'$ec'";
                    $error = 1;
                    return;
                };
                my $close_error = sub ( $cmd, $msg, $ec ) {    # file got deleted while running?
                    write_socket $socket->$*, 'STDOUT', "ERROR: closing MSG:'$msg' EC:'$ec'";
                    $error = 2;
                    return;
                };
                my $read_handler = sub ( $stop, $line ) {
                    chomp $line;
                    write_socket $socket->$*, 'STDOUT', $line;
                    return;
                };

                run_open join( ' ', 'sudo', '/usr/bin/genesis', @args, '2>&1' ), $close_error, $open_error, $read_handler;
                return $error;
            },
            RECEIVE => sub(@args) {

                my $arg = am_dio_input @args;
                return 'DISABLED' unless $arg;
                return $arg;
            }
        },
    };
}

sub _client_protocol ( $socket ) {
    return {
        base_protocol(),
        FAILED => {
            SEND    => sub(@) { },
            RECEIVE => sub(@) {
                say 'ERROR: Execution failed.';
                return 1;
            }
        },
        SUCCESS => {
            SEND    => sub(@) { },
            RECEIVE => sub(@) {
                say 'Execution successful.';
                return 1;
            }
        },
    };
}

################################

sub am_dio_server($socket_path) {

    die 'ERROR: Incomplete config' if ( !$socket_path );
    return sub(@args) {

        my $server = server( $socket_path, sub($s) { return _server_protocol($s); } );
        return $server->(@args);
    };
}

sub am_dio_client($socket_path) {

    die 'ERROR: Incomplete config' if ( !$socket_path );
    return sub(@args) {

        my $client = client( $socket_path, sub($s) { return _client_protocol($s); } );
        say 'Waiting for execution slot...';
        $client->(@args);
        $client->('READ');
        $client->('CLOSE');
        return;
    };
}

1;
