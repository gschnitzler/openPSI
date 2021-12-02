package Plugins::LetsEncrypt::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Read qw(read_config load_config);
use IO::Config::Check qw(check_config);

use Plugins::LetsEncrypt::Cmds::List qw(import_list);
use Plugins::LetsEncrypt::Cmds::Update qw(import_update);
use Plugins::LetsEncrypt::Cmds::Accounts qw(import_accounts);

use lib '/data/psi/cfgen';
use Plugins::Build::Filter::Secrets qw(add_secrets_tree);    # cfgen Plugin

our @EXPORT_OK = qw(import_hooks);

####################################################

my $check = {
    '*' => {                                                 # domain name
        KEY => [qr/^(SECRETS:.+)/x],                         # LetsEncrypt priv/domain key
        ID  => [qr/^(SECRETS:.+)/x],                         # LetsEncrypt API key_id
    }
};

sub import_loader ( $debug, $query ) {

    my $config_path  = $query->('CONFIG_PATH');
    my $secrets_path = $query->('SECRETS_PATH');
    my $letsencrypt  = check_config(
        $debug,
        {
            name       => 'LetsEncrypt',
            config     => load_config( read_config( $debug, $config_path ) ),
            definition => $check,
        }
    );

    add_secrets_tree( $query->('secrets'), $letsencrypt );
    return {
        state => {
            secrets_path       => sub(@) { return $secrets_path },
            letsencrypt_config => sub(@) { return dclone $letsencrypt },
        },
        scripts => {},
        macros  => {},
        cmds    => [ import_update, import_list, import_accounts ],
    };
}

sub import_hooks($self) {
    return {
        name    => 'LetsEncrypt',
        require => [ 'DNS', 'Cloudflare', 'Secrets' ],
        loader  => \&import_loader,
        data    => {
            CONFIG_PATH  => 'CONFIG_PATH',
            SECRETS_PATH => 'SECRETS_PATH',
            secrets      => 'state secrets'
        }
    };
}
