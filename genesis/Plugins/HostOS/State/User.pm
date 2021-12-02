package Plugins::HostOS::State::User;

use ModernStyle;
use Exporter qw(import);

use Plugins::HostOS::Libs::Parse::Users qw(read_users);

our @EXPORT_OK = qw(get_user);

# this is a wrapper because $param is pased to state
sub get_user ( ) {

    return read_users();

}
1;
