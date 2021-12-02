package Plugins::Config::HostOS::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Templates::Read qw(read_templates);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $templates = read_templates( $debug, $config_path );

    return {
        state => {
            hostos => sub () {
                return dclone $templates;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'HostOS',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

