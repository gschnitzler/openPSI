package AM::Socket::Client;

use ModernStyle;
use Exporter qw(import);
use IO::Socket::UNIX;
use Carp;
use Data::Dumper;

use AM::Socket qw(read_socket write_socket broken_pipe get_socket_msg protocol_unsupported);

our @EXPORT_OK = qw(client);

######################################

sub _client_handler ( $protocol ) {

    return sub ($line) {
        my ( $action, @args ) = get_socket_msg($line);

        # clients don't respond
        return $protocol->{$action}->{RECEIVE}->(@args) if exists $protocol->{$action};
        return protocol_unsupported( $protocol, $action );
    };
}

##################################

sub client ( $socket_path, $load_protocol ) {

    my $server;
    my $handler = _client_handler $load_protocol->( \$server );
    my $cmds    = {
        WRITE => sub ( $handler, @args ) {
            return write_socket( $server, @args );
        },
        READ => sub ( $handler, @args ) {
            return read_socket( $server, $handler, @args );
        },
        CLOSE => sub(@args) {
            return $server->close;
        },
        '*' => sub($arg) {
            confess "ERROR: invalid argument '$arg'";
        }
    };

    $server = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Peer => $socket_path,
    );

    return sub ( $cmd, @args ) {
        local $SIG{PIPE} = broken_pipe();
        confess "ERROR: could not open socket $socket_path" if ( !$server || !$server->$* );
        return $cmds->{'*'}->($cmd) if !exists $cmds->{$cmd};
        return $cmds->{$cmd}->( $handler, @args );
    };
}

1;
