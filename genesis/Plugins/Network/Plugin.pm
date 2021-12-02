package Plugins::Network::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Network::System::GetIP qw(get_ip check_ip);
use Plugins::Network::Cmds::State qw(import_state);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ($debug, $query) {

    # check if the system we are on has any interface configured that matches our config.
    # just to make sure everything is ok
    check_ip( $query->('network') );

    return {
        state => {
            network => sub (@arg) {
                return get_ip( $query->('network'), @arg );
            }
        },
        scripts => {},
        macros  => {},
        cmds    => [ import_state, ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Network',
        require => [],
        loader  => \&import_loader,
        data    => { network => 'machine self NETWORK' }
    };
}

