package Config::Inotify::Handler;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;

use AM::Socket qw(base_protocol write_socket);
use AM::Socket::Client qw(client);
use PSI::Console qw(print_table);
use IO::Config::Check qw(socket_exists);

our @EXPORT_OK = qw(wait_on_socket queue_handler);

#########################

sub _load_protocol($s) {
    return {
        base_protocol(),
        QUEUE => {
            SEND => sub(@args) {
                return write_socket( $s->$*, 'QUEUE', @args );
            },
            RECEIVE => sub(@) { },
        }
    };
}

sub wait_on_socket ( $socket_path, $timeout ) {

    my $counter = $timeout;
    while ( !socket_exists($socket_path) ) {
        say "INIT CONFIG: waiting for socket ($socket_path): $counter";
        sleep 1;
        $counter--;
        confess "ERROR: no socket at $socket_path" if $counter < 0;
    }
    return;
}

sub queue_handler ($socket_path) {

    return sub ( $fp, $event, $args ) {    # just offload inotify events to a socket
        print_table $fp, $event, ": received\n";
        my $client = client( $socket_path, \&_load_protocol );
        my $ec     = $client->( 'WRITE', 'QUEUE', 'START', $fp, $event );
        $client->('CLOSE');
        return $ec;
    };
}
1;
