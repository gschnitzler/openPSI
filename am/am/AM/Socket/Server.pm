package AM::Socket::Server;

use ModernStyle;
use Exporter qw(import);
use IO::Socket::UNIX;
use IO::Select;
use Carp;
use Data::Dumper;

use InVivo qw(kexists);
use IO::Config::Check qw(file_exists socket_exists);
use AM::Socket qw(broken_pipe protocol_unsupported get_socket_msg);

our @EXPORT_OK = qw(server);

######################################

sub _server_handler ( $protocol ) {

    return sub ($line) {

        my ( $action, @args ) = get_socket_msg($line);
        return protocol_unsupported( $protocol, $action ) if ( !kexists( $protocol, $action, 'SEND' ) || !kexists( $protocol, $action, 'RECEIVE' ) );
        my $return_code = $protocol->{$action}->{SEND}->( $protocol->{$action}->{RECEIVE}->(@args) );
        $return_code ? $protocol->{FAILED}->{SEND}->() : $protocol->{SUCCESS}->{SEND}->();
        return $return_code;
    };
}

sub _remove_socket($socket_path) {

    local ( $!, $? );
    unlink $socket_path or print "$? $!" if ( file_exists $socket_path or socket_exists $socket_path);
    return;
}

##################################

sub server ( $socket_path, $load_protocol ) {

    confess 'ERROR: no socket path given' unless $socket_path;

    my $client  = '';                                                # global is needed to pass a reference to protocol.
    my $handler = _server_handler( $load_protocol->( \$client ) );

    return sub(@post_init) {

        print "Preparing socket $socket_path: ";
        _remove_socket($socket_path);

        local $SIG{PIPE} = broken_pipe();
        local $SIG{TERM} = sub { return _remove_socket($socket_path) };
        local $SIG{INT}  = sub { return _remove_socket($socket_path) };

        my $socket = IO::Socket::UNIX->new(
            Type   => SOCK_STREAM(),
            Local  => $socket_path,
            Listen => 1000,
        );
        my $select = IO::Select->new($socket);

        chmod oct(770), $socket_path or die "ERROR: could not chnmod $socket_path";
        say 'OK';

        # run a post init callback.
        # could be used for spawning workers after socket creation or whatever
        if ( $post_init[0] && ref $post_init[0] eq 'CODE' ) {
            my $cmd = shift @post_init;
            $cmd->(@post_init);
        }

        # boilerplate IO::Select
        while ( my @ready = $select->can_read ) {

            foreach my $c (@ready) {

                $client = $c;    # update the client fh used in protocol
                if ( $client == $socket ) {

                    my $client_socket = $socket->accept() or confess "Can't accept connection: $!\n";
                    $select->add($client_socket);
                    next;
                }

                # pass the first received line to the handler, which in turn might block if the protocol triggers a multi msg exchange with delays.
                # we could fork off the handler with a dcloned protocol or at least dereferenced $client filehandle.
                # for now, just block until the handler is finished: the fork overhead would just delay the small msgs this module is used for.
                my $line = readline $client;
                if ($line) {
                    my $return_code = $handler->($line);    # return value could be used for error handling,
                }
                else {
                    $select->remove($client);
                    $client->close;
                }
            }
        }
        say 'EOF from socket.';
        return 1;
    };
}

1;
