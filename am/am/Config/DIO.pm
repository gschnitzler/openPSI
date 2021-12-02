package Config::DIO;

use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(am_dio_config);

#########################
sub am_dio_config {

    return {
        socket => '/tmp/dio.sock',

        gid    => '[% machine.self.USER_ACCOUNTS.GROUPS.psdev.GID %]',
        uid    => '[% machine.self.HOST_UID %]',
        #uid => '1102',
        #gid => '2001',
    };
}
1;
