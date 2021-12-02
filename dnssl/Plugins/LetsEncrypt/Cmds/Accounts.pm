package Plugins::LetsEncrypt::Cmds::Accounts;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table print_line);
use PSI::Parse::File qw(write_file);
use API::ACME2 qw(create_accounts);

use Plugins::LetsEncrypt::Lib::GetWildcards qw(get_wildcards);

our @EXPORT_OK = qw(import_accounts);

#######################################

sub _export_config ( $secrets_path, $t ) {

    my $config = {};
    foreach my $account_domain ( keys $t->%* ) {

        my $account       = $t->{$account_domain};
        my $id            = $account->{ID};
        my $key           = $account->{KEY};
        my $id_file_name  = join( '.', 'global.letsencrypt.api', $account_domain, 'id' );
        my $key_file_name = join( '.', 'global.letsencrypt.api', $account_domain, 'key' );

        print_table 'Saving', $account_domain, ': ';
        write_file(
            {
                PATH    => join( '/', $secrets_path, $id_file_name ),
                CONTENT => [$id],
            }
        );
        $config->{$account_domain}->{ID} = join( ':', 'SECRETS', $id_file_name );    # override entries with config version
        say $id_file_name;

        print_table 'Saving', $account_domain, ': ';
        write_file(
            {
                PATH    => join( '/', $secrets_path, $key_file_name ),
                CONTENT => [$key],
            }
        );
        $config->{$account_domain}->{KEY} = join( ':', 'SECRETS', $key_file_name );    # override entries with config version
        say $key_file_name;
    }

    return $config;
}

sub _create_accounts ( $query, @args ) {

    my $wanted_domain      = shift @args;
    my $dns                = $query->('dns');
    my $secrets_path       = $query->('secrets_path');
    my $letsencrypt_config = $query->('letsencrypt_config');
    my $wildcards          = get_wildcards($dns);

    if ($wanted_domain) {
        die "ERROR: unknown domain '$wanted_domain'" if ( !exists $wildcards->{$wanted_domain} );
        $wildcards = { "$wanted_domain" => $wildcards->{$wanted_domain} };
    }

    my $letsencrypt_accounts   = create_accounts( $wildcards, $letsencrypt_config );
    my $new_letsencrypt_config = _export_config( $secrets_path, $letsencrypt_accounts );

    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Quotekeys = 0;

    print_line 'Add this to config';
    say Dumper $new_letsencrypt_config;
    return;
}

###########################################
sub import_accounts () {

    my $struct = {};

    $struct->{create}->{ssl}->{accounts} = {

        CMD  => \&_create_accounts,
        DESC => 'Creates LetsEncrypt Domain Accounts',
        HELP => [ 'Creates LetsEncrypt Domain Accounts', 'usage:', 'create ssl accounts [root domain]' ],
        DATA => {
            letsencrypt_config => 'state letsencrypt_config',
            dns                => 'state dns',
            secrets_path       => 'state secrets_path'
        }
    };

    return $struct;
}

1;
