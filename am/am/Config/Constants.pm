package Config::Constants;

use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(am_constants);

#########################
sub am_constants {

    my $data_base_path    = '/tmp/test';
    my $program_base_path = './etl';

    return {
        socket => '/tmp/queue.sock',
        path   => {
            tm => {
                out => "$data_base_path/tm/out",    # TaskManager puts files to be processed here
            },
            am => {
                in      => "$data_base_path/am/in",         # ArchiveManager receives files to be processed here
                out     => "$data_base_path/am/out",        # et should put processed files here, via args
                archive => "$data_base_path/am/archive",    # et should put log files here, via args
            },
            ld => {
                in => "$data_base_path/ld/in",              # Loader reads its files from here
            }
        },
        handler => {
            qbo  => "$program_base_path/qbo.sh",
            loop => "$program_base_path/loop.sh",
            xero => "$program_base_path/xero.sh",
        },
        archive => {
            'gschnitzler' => {
                port             => '1022',
                user             => 'gschnitzler',
                key              => '/tmp/bla/key',
                known_hosts_file => '/tmp/bla/knownhosts',
                root_dir         => '/tmp',
            }
        },
    };
}
1;
