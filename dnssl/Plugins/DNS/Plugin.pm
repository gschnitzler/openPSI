package Plugins::DNS::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Read qw(read_config load_config);
use IO::Config::Check qw(check_config);

our @EXPORT_OK = qw(import_hooks);

####################################################

my $check = {
    '*' => {
        '*' => {
            '*' => {
                '*' => {
                    'proxied'   => [qr/^([01])/x],
                    'type'      => [qr/^((?:A|TXT|MX|CAA))/x],
                    'name'      => [qr/^(.+)/x],
                    'content'   => [qr/^(.+)/x],
                    'zone_id'   => [qr/^(.+)/x],
                    'id'        => [qr/^(.+)/x],
                    'zone_name' => [qr/^(.+)/x],
                    'priority'  => [qr/^(\d+)/x]
                },
            }
        }
    }
};

sub import_loader ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $dns         = check_config(
        $debug,
        {
            name       => 'DNS',
            config     => load_config( read_config( $debug, $config_path ) ),
            definition => $check,
        }
    );

    return {
        state   => { dns => sub(@) { return dclone $dns }, },
        scripts => {},
        macros  => {},
        cmds    => [],
    };
}

sub import_hooks($self) {
    return {
        name    => 'DNS',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

