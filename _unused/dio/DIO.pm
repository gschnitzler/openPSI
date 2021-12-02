package DIO;

use DIO::ModernStyle;
use Exporter qw(import);

our @EXPORT_OK = qw(dio_client_handler dio_server_handler);

#######################

my $dio = {
    CONFIG => {

        # /tmp is used instead of /run, because /run is root only.
        SOCK_PATH => '/tmp/dio.sock',
    },
    SOCKET => '',
};

# in client context, return !=0 means EOF
# in server context, RECEIVE return values are just fed into SEND. could be anything.
# in server context, SEND return values could be evaluated by the server program.
my $protocol = {
    DIO_STDOUT => {
        SEND => sub($args) {
            _send_msg( $dio->{SOCKET}, 'DIO_STDOUT', $args );
            return;
        },
        RECEIVE => sub($args) {
            say $args;
            return;
        }
    },
    DIO_FAILED => {
        SEND => sub(@) {
            _send_msg( $dio->{SOCKET}, 'DIO_FAILED' );
            return;
        },
        RECEIVE => sub(@) {
            say "ERROR: Execution failed.";
            return 1;
        }
    },
    DIO_SUCCESS => {
        SEND => sub(@) {
            _send_msg( $dio->{SOCKET}, 'DIO_SUCCESS' );
            return;
        },
        RECEIVE => sub(@) {
            say 'Execution successfull';
            return 1;
        }
    },
    DIO_GENESIS => {
        SEND => sub ($args) {

            if ( $args eq 'DISABLED' ) {
                _send_msg->( $dio->{SOCKET}, 'DIO_STDOUT', 'ERROR: command unavailable.' );
                return 1;
            }

            open( my $fh, '-|', "sudo /usr/bin/genesis $args 2>&1" );
            while ( my $line = <$fh> ) {
                chomp $line;
                _send_msg->( $dio->{SOCKET}, 'DIO_STDOUT', $line );

            }
            close $fh;

            # CHILD_ERROR_NATIVE holds error codes from close
            # this could be used by the client or server to take action, after a genesis command failed.
            return ${^CHILD_ERROR_NATIVE};
        },
        RECEIVE => sub($args) {
            my @allowed_commands = (

                #
                qr/^test\ .*/,
                qr/^restart\ container\ .*/,
                qr/^stage\ .*/,
                qr/^start container\ .*/,
                qr/^stop container\ .*/,
                qr/^copy etl log of\ .*/,
                qr/^restart production container\ .*/,

            );

            $args =~ s/[^a-zA-Z0-9§ \.\-_\/]//g;    # only allow characters that could be used as genesis commands

            for my $allowed (@allowed_commands) {
                return $args if ( $args =~ /$allowed/ );
            }
            return 'DISABLED';
        }
    },
};

#######################

sub _socket_msg($line) {
    chomp $line;
    $line =~ /^([^ ]+)/;

    my $type = $1;
    $line =~ /^([^ ]+)[ ](.*)/;
    my $args = $2;

    return $type, $args;
}

sub _send_msg ( $socket, $type, @args ) {
    say $socket join( ' ', $type, @args );
    return;
}

sub _dio_unsupported ( $proto, $args ) {

    $proto->{DIO_STDOUT}->{SEND}->("Protocol ERROR: $args");
    $proto->{DIO_FAILED}->{SEND}->();
    return 1;
}

sub _srv_handler ( $proto, $line ) {

    my ( $action, $args ) = _socket_msg($line);

    return _dio_unsupported( $proto, $action ) if ( !exists( $proto->{$action} ) );

    my $return_code = $proto->{$action}->{SEND}->( $proto->{$action}->{RECEIVE}->($args) );

    if ($return_code) {
        $proto->{DIO_FAILED}->{SEND}->();
    }
    else {
        $proto->{DIO_SUCCESS}->{SEND}->();
    }
    return $return_code;
}

sub _client_handler ( $proto, $line ) {

    my ( $action, $args ) = _socket_msg($line);

    # clients dont respond
    return $proto->{$action}->{RECEIVE}->($args) if ( exists( $proto->{$action} ) );
    return _dio_unsupported( $proto, $action );
}

#######################

sub dio_server_handler() {

    $dio->{HANDLER} = sub ($line) { _srv_handler( $protocol, $line ); };
    return $dio;
}

sub dio_client_handler() {

    $dio->{HANDLER} = sub ($line) { _client_handler( $protocol, $line ); };
    return $dio;
}
1;
