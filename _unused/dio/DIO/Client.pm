package DIO::Client;

use DIO::ModernStyle;
use DIO qw(dio_client_handler);
use IO::Socket::UNIX;
use Exporter qw(import);

our @EXPORT_OK = qw(dio_client);

sub _read_socket ( $dio ) {

    my $socket = $dio->{SOCKET};

    #my $filter = $protocol->{helper}->{client_filter};

    say 'Reading answer from server:';

    while ( my $line = <$socket> ) {

        #my ( $action, $args ) = $filter->($line);

        #die "ERROR: unknown action $action" unless exists( $protocol->{client}->{$action} );
        #my $success = $protocol->{client}->{$action}->($args);
        my $eof = $dio->{HANDLER}->($line);
        last if ($eof);
    }
    return;
}

sub _write_socket ( $socket, $type, $args ) {

    die 'ERROR: Server not running' unless $socket;
    print 'waiting for execution slot... ';
    say $socket join( ' ', $type, $args );
    say 'OK';
    return;
}

sub dio_client() {

    return sub(@args) {
        my $dio = dio_client_handler();

        $dio->{SOCKET} = IO::Socket::UNIX->new(
            Type => SOCK_STREAM(),
            Peer => $dio->{CONFIG}->{SOCK_PATH},
        );

        _write_socket( $dio->{SOCKET}, @args );
        _read_socket($dio);
        close $dio->{SOCKET};
        return;
    };

}
