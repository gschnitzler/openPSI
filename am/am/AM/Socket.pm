package AM::Socket;

use ModernStyle;
use Exporter qw(import);
use Carp;
use Data::Dumper;

our @EXPORT_OK = qw(base_protocol protocol_unsupported broken_pipe socket_msg get_socket_msg read_socket write_socket new_socket);

######################################

sub broken_pipe() {
    return sub { confess 'ERROR: socket closed during execution' };
}

sub get_socket_msg($msg) {
    chomp $msg;
    return split( /\0/, $msg );
}

sub protocol_unsupported ( $protocol, @args ) {

    $protocol->{STDOUT}->{SEND}->("Protocol ERROR: @args");
    $protocol->{FAILED}->{SEND}->();
    return 1;
}

# blocking
sub read_socket ( $socket, $handler, @ ) {

    while ( my $line = <$socket> ) {
        last if $handler->($line);    # handler returns true on EOF
    }
    return;
}

sub write_socket ( $socket, @args ) {

    confess 'ERROR: Server not running' unless $socket;
    say $socket join( "\0", @args );
    return;
}

sub base_protocol() {

    # in client context, return !=0 means EOF
    # in server context, RECEIVE return values are just fed into SEND. could be anything.
    # in server context, SEND return values could be evaluated by the server program.
    # STDOUT, FAILED and SUCCESS are expected by Client and Server implementations.
    # they can be overloaded for multi msg protocols
    return (
        STDOUT => {
            SEND    => sub(@) { },
            RECEIVE => sub(@args) {
                say join( ' ', @args );
                return 0;
            },
        },
        FAILED => {
            SEND    => sub(@) { },
            RECEIVE => sub(@) { },
        },
        SUCCESS => {
            SEND    => sub(@) { },
            RECEIVE => sub(@) { },
        }
    );
}

1;
