package Plugins;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use IO::Config::Check qw(check_config);

our @EXPORT_OK = qw(plugin_config);

########################

my $config_path         = "/data/psi/config";
my $private_config_path = "/data/psi/config-private";
my $cache_path          = '/tmp/cfgen_cache';
my $config              = {
    Accounts => {
        path => 'Plugins/Config/Accounts',
        data => { CONFIG_PATH => "$private_config_path/Accounts" },
    },
    Bootstrap => {
        path => 'Plugins/Config/Bootstrap',
        data => { CONFIG_PATH => "$config_path/Bootstrap" },
    },
    Build => {
        path => 'Plugins/Build',
        data => { CONFIG_PATH => '' },
    },
    Cluster => {
        path => 'Plugins/Config/Cluster',
        data => {
            CONFIG_PATH => "$private_config_path/Cluster",
            CACHE       => "$cache_path/Cluster",
        },
    },
    Container => {
        path => 'Plugins/Config/Container',
        data => {
            CONFIG_PATH         => "$config_path/Container",
            PRIVATE_CONFIG_PATH => "$private_config_path/Container",
            CACHE               => "$cache_path/Container",
        },
    },
    Genesis => {
        path => 'Plugins/Config/Genesis',
        data => { CONFIG_PATH => '' },
    },
    HostOS => {
        path => 'Plugins/Config/HostOS',
        data => { CONFIG_PATH => "$config_path/HostOS" },
    },
    Images => {
        path => 'Plugins/Config/Images',
        data => {
            CONFIG_PATH => "$config_path/Images",
            CACHE       => "$cache_path/Images",
        },
    },
    Paths => {
        path => 'Plugins/Config/Paths',
        data => { CONFIG_PATH => "$config_path/Paths" },
    },
    Roles => {
        path => 'Plugins/Config/Roles',
        data => { CONFIG_PATH => "$config_path/Roles" },
    },
    Secrets => {
        path => 'Plugins/Config/Secrets',
        data => { CONFIG_PATH => '/data/local_config/secrets' },
    },
    Services => {
        path => 'Plugins/Config/Services',
        data => {
            CONFIG_PATH => "$config_path/Services",
            CACHE       => "$cache_path/Services",
        },
    },
};

my $check = {
    '*' => {
        path => [ qr/^(.*)/x, 'dircheck' ],
        data => {
            CONFIG_PATH         => [ qr/(.*)/x, 'dircheck' ],
            PRIVATE_CONFIG_PATH => [ qr/(.*)/x, 'dircheck' ],
            CACHE               => [ qr/(.*)/x, 'dircheck' ]
        },
    }
};

sub plugin_config ($debug) {

    my $checked_config = check_config(
        $debug,
        {
            name       => 'cfgen',
            config     => $config,
            definition => $check,
            force_all  => 0
        }
    );

    my @plugins = ();

    foreach my $k ( keys( $checked_config->%* ) ) {
        push @plugins, { $checked_config->{$k}->%* };
    }

    return @plugins;
}
