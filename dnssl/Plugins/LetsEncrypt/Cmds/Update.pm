package Plugins::LetsEncrypt::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use PSI::Parse::File qw(write_file);
use API::ACME2 qw(authorize_domain_acme2);

use Plugins::LetsEncrypt::Lib::GetWildcards qw(get_wildcards);

our @EXPORT_OK = qw(import_update);

my $PREFIX  = 'letsencrypt';
my $POSTFIX = {
    CERT         => 'crt',
    PRIV         => 'priv',
    INTERMEDIATE => 'intermediate'
};

#######################################

sub _export_config ( $secrets_path, $t ) {

    #local $Data::Dumper::Indent    = 1;
    #local $Data::Dumper::Terse     = 1;
    #local $Data::Dumper::Quotekeys = 0;

    foreach my $wildcard ( keys $t->%* ) {

        print_table 'Saving', $wildcard, ': ';
        my $ssl    = $t->{$wildcard};
        my $type   = 'host';
        my $domain = $wildcard;

        if ( $domain =~ s/^[*][.]// ) {
            $type = 'wildcard';
        }

        my $prefix = join( '-', $PREFIX, $type );

        foreach my $k ( keys $ssl->%* ) {

            my $postfix   = $POSTFIX->{$k};
            my $filename  = join( '.', $prefix, $domain, $postfix );
            my $full_path = join( '/', $secrets_path, $filename );

            write_file(
                {
                    PATH    => $full_path,
                    CONTENT => [ $ssl->{$k} ],
                }
            );
        }
        say 'OK';
    }
    return;
}

sub _update_ssl ( $query, @args ) {

    my $wanted_domain = shift @args;
    my $cloudflare    = $query->('cloudflare');
    my $dns           = $query->('dns');
    my $secrets_path  = $query->('secrets_path');
    my $letsencrypt_config   = $query->('letsencrypt_config');
    my $wildcards     = get_wildcards($dns);

    if ($wanted_domain) {

        die "ERROR: unknown domain '$wanted_domain'" if ( !exists $cloudflare->{$wanted_domain} || !exists $wildcards->{$wanted_domain} );

        # here it would be nice to also accept subdomains.
        # sometimes only a single subdomain is added, and needs a cert, without requiring a complete ssl update

        $wildcards  = { "$wanted_domain" => $wildcards->{$wanted_domain} };
        $cloudflare = { "$wanted_domain" => $cloudflare->{$wanted_domain} };
    }

    my $ssl_certs = authorize_domain_acme2( $wildcards, $cloudflare, $letsencrypt_config );
    _export_config( $secrets_path, $ssl_certs );

    return;
}

###########################################
sub import_update () {

    my $struct = {};

    $struct->{update}->{ssl}->{certs} = {

        CMD  => \&_update_ssl,
        DESC => 'Updates LetsEncrypt SSL certs',
        HELP => [ 'Updates LetsEncrypt SSL certs', 'usage:', 'update ssl certs [root domain]' ],
        DATA => {
            cloudflare         => 'state cloudflare',
            dns                => 'state dns',
            secrets_path       => 'state secrets_path',
            letsencrypt_config => 'state letsencrypt_config'
        }
    };

    return $struct;
}

1;
