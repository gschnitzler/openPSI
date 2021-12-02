package Plugins::Config::Roles::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Check qw(check_config);
use IO::Config::Read qw(read_config load_config);

our @EXPORT_OK = qw(import_hooks);

# roles define 2 things:
# - what genesis Plugins should be included
# - what config should NOT be included
#
# right now, roles can not be mixed

my $check_role = {
    '*' => {
        USE_PLUGINS => { '*' => [qr/^\s*(yes|no)/x], },
        DROP_CONFIG => { '*' => [qr/^\s*(.+)/x], }
    }
};

#####################

sub import_loader ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $roles       = load_config( read_config($debug, $config_path) );

    my $assembled_roles = check_config(
        $debug,
        {   name       => 'Roles',
            config     => $roles,
            definition => $check_role,
            force_all  => 1
        }
    );

    return {
        state => {
            roles => sub () {
                return dclone $assembled_roles;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Roles',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

