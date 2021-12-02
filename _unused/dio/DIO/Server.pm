package DIO::Server;

use DIO::ModernStyle;
use DIO qw(dio_server_handler);
use IO::Socket::UNIX;
use Exporter qw(import);

our @EXPORT_OK = qw(dio_server);

sub dio_server() {

    my $dio       = dio_server_handler();
    my $SOCK_PATH = $dio->{CONFIG}->{SOCK_PATH};

    die 'ERROR: no socket path given' unless $SOCK_PATH;
    unlink $SOCK_PATH if ( -e $SOCK_PATH );

    # socket removal happens before the below code is executed.
    # this gives some room for scenarios like priv dropping
    #####

    return sub {

        my $server = IO::Socket::UNIX->new(
            Type   => SOCK_STREAM(),
            Local  => $SOCK_PATH,
            Listen => 1,
        );
        system("chmod 770 $SOCK_PATH");

        $dio->{SOCKET} = $server->accept() or die("Can't accept connection: $!\n");
        my $socket = $dio->{SOCKET};

        while ( my $line = <$socket> ) {

            my $return_code = $dio->{HANDLER}->($line);

            # $return_code could be used to take action. true means error.
            # could be used to terminate program or write out an error log
            # failed commands may lead to undefined state.
            # to prevent further action in such a situation, the server could terminate, requiring the operator to investigate.
            # however, even a simple typo in the command line would trigger this.
            # which is not exactly a nice user experience.
            # as the available commands can not inflict much harm, lets drop it.

            #$protocol->{SRV_HANDLER}->();
            #my ( $action, $args ) = $protocol->{helper}->{server_filter}->($line);

            #if ( exists( $protocol->{server}->{$action} ) ) {
            #    _die_on_error( $protocol->{helper}->{say_client}, $protocol->{server}->{$action}->($args) );

            #}
            #else {
            #    $protocol->{helper}->{say_client}->( 'DIO_STDOUT', 'ERROR: Protocol mismatch' );
            #    $protocol->{helper}->{say_client}->('DIO_FAILED');
            #}

            $dio->{SOCKET} = $server->accept() or die("Can't accept connection: $!\n");
            $socket = $dio->{SOCKET};

        }
        say 'EOF from socket';
        return;
    };
}
