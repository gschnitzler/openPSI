package Plugins::Config::Bootstrap::Plugin;

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
            bootstrap => sub () {
                return dclone $templates->{Templates};
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Bootstrap',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

