package Config::Inotify;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use Config::Constants qw(am_constants);
use Config::Inotify::Handler qw(wait_on_socket queue_handler);

our @EXPORT_OK = qw(am_inotify_config);

Readonly my $SOCKET_TIMEOUT => 5;

#########################
# Demo implementation
sub am_inotify_config () {

    my $c           = am_constants();
    my $path        = $c->{path};
    my $socket_path = $c->{socket};
    my $handler     = queue_handler($socket_path);

    wait_on_socket( $socket_path, $SOCKET_TIMEOUT );

    return {
        global => {
            process_stale => 1,    # rerun stale files on startup?
        },
        paths => {
            $path->{tm}->{out} => {    # handled path
                IN_CLOSE_WRITE => {    # inotify event
                    handler => $handler,    # handler program to call
                    args    => {            # additional arguments passed to the handler
                    }
                }
            },
            $path->{am}->{in} => {
                IN_MOVED_TO => {            # inotify event
                    handler => $handler,    # handler program to call
                    args    => {            # additional arguments passed to the handler
                    }
                }
            },
            $path->{am}->{out} => {
                IN_CLOSE_WRITE => {         # inotify event
                    handler => $handler,    # handler program to call
                    args    => {            # additional arguments passed to the handler
                    }
                }
            },
            $path->{ld}->{in} => {
                IN_MOVED_TO => {            # inotify event
                    handler => $handler,    # handler program to call
                    args    => {            # additional arguments passed to the handler
                    },
                }
            },
            $path->{am}->{archive} => {
                IN_CLOSE_WRITE => {         # inotify event
                    handler => $handler,    # handler program to call
                    args    => {            # additional arguments passed to the handler
                    }
                }
            },
        }
    };
}
1;
