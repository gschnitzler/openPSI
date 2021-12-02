package Plugins;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use lib '/data/psi/cfgen';
use IO::Config::Check qw(check_config);

our @EXPORT_OK = qw(plugin_config);

########################

my $psi               = '/data/psi';
my $config_path       = "$psi/config";
my $local_config_path = '/data/local_config';
my $config            = {
    Secrets => {
        path => '../cfgen/Plugins/Config/Secrets',
        data => { CONFIG_PATH => "$local_config_path/secrets" },
    },
    DNS => {
        path => 'Plugins/DNS',
        data => { CONFIG_PATH => "$local_config_path/dns" },
    },
    Cloudflare => {
        path => 'Plugins/Cloudflare',
        data => { CONFIG_PATH => "$config_path/Cloudflare" },
    },
    LetsEncrypt => {
        path => 'Plugins/LetsEncrypt',
        data => {
            CONFIG_PATH  => "$config_path/LetsEncrypt",
            SECRETS_PATH => "$local_config_path/secrets",
        },
    },
};

my $check = {
    '*' => {
        path => [ qr/^(.*)/x, 'dircheck' ],
        data => {
            CONFIG_PATH  => [ qr/^(.*)/x, 'dircheck' ],
            SECRETS_PATH => [ qr/^(.*)/x, 'dircheck' ],
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
