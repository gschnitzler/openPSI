package Config::Forker;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Config::Constants qw(am_constants);
use Config::Forker::Handler qw(default_handler move_handler success_handler launch_handler sftp_client_handler);

our @EXPORT_OK = qw(am_forker_config);

#########################
# Demo implementation
sub am_forker_config () {

    my $config         = am_constants();
    my $socket_path    = $config->{socket};
    my $path           = $config->{path};
    my $archive_config = $config->{archive};
    my $et_handler     = $config->{handler};

    return {
        global => {
            max_jobs    => 4,               # number of concurrent running jobs per path
            socket_path => $socket_path,    # socket to create and use
        },
        paths => {
            '*' => {                        # default handler
                handler => \&default_handler,
            },
            $path->{tm}->{out} => {         # handled path
                IN_CLOSE_WRITE => {         # handled event
                    handler => \&move_handler,    # must be a code ref
                    args    => {                  # additional arguments passed to the handler
                        move_to => $path->{am}->{in}
                    },
                }
            },
            $path->{am}->{in} => {
                IN_MOVED_TO => {
                    handler => \&launch_handler,
                    args    => {
                        handler => $et_handler,
                        out_dir => $path->{am}->{out}
                    },
                }
            },
            $path->{am}->{out} => {
                IN_CLOSE_WRITE => {
                    handler => \&move_handler,
                    args    => {
                        move_to => $path->{ld}->{in},
                    },
                }
            },
            $path->{ld}->{in} => {
                IN_MOVED_TO => {
                    handler => \&success_handler,
                    args    => {
                        say => 'cleaning up demo',
                    },
                }
            },
            $path->{am}->{archive} => {
                IN_CLOSE_WRITE => {
                    handler => \&sftp_client_handler,
                    args    => {
                        servers => $archive_config
                    },
                }
            },
        }
    };
}
1;
