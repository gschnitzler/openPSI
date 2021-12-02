package Plugins::Container::Macros::Container;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(get_container_macros);

sub get_container_macros() {

    return {
        restart => {
            production => {
                # this is used to let developers restart production containers after staging via DIO.
                # be sure to adapt DIOs own allowed_commands to enable new entries
                container => {
                    'ps-www' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-www_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                    'ps-etl' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-etl_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                    'ps-myclient' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-myclient_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                    'ps-app' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-app_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                    'ps-intranet' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-intranet_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                    'ps-myfinance' => {
                        MACRO => [ 'remote normal de-cluster2 \'sudo genesis restart container ps-myfinance_production\'' ],
                        HELP  => ['restarts production container on remote host'],
                        DESC  => 'restarts production container on remote host'
                    },
                }
            },
        },
    };
}

1;
