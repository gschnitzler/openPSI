package Plugins::Cloudflare::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Read qw(read_config load_config);
use IO::Config::Check qw(check_config);

use lib '/data/psi/cfgen';
use Plugins::Build::Filter::Secrets qw(add_secrets_tree);    # cfgen Plugin
use Plugins::Cloudflare::Cmds::List qw(import_list);
use Plugins::Cloudflare::Cmds::Update qw(import_update);

our @EXPORT_OK = qw(import_hooks);

####################################################

my $check = {
    '*' => {
        USERNAME => [qr/^(.+)/x],                            # cloudflare username
        API_KEY  => [qr/^(SECRETS:.+)/x],                    # cloudflare API key
    }
};

sub import_loader ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $cloudflare  = check_config(
        $debug,
        {   name       => 'Cloudflare',
            config     => load_config( read_config( $debug, $config_path ) ),
            definition => $check,
        }
    );

    add_secrets_tree( $query->('secrets'), $cloudflare );

    return {
        state   => { cloudflare => sub(@) { return dclone $cloudflare }, },
        scripts => {},
        macros  => {},
        cmds => [ import_list, import_update ],
    };
}

sub import_hooks($self) {
    return {
        name    => 'Cloudflare',
        require => [ 'DNS', 'Secrets' ],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', secrets => 'state secrets', }
    };
}

