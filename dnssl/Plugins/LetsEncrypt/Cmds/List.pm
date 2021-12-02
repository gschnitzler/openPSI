package Plugins::LetsEncrypt::Cmds::List;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::RunCmds qw(run_open);
use PSI::Console qw(print_table);

use Plugins::LetsEncrypt::Lib::GetWildcards qw(get_wildcards);

our @EXPORT_OK = qw(import_list);

#######################################

sub _get_cert_validity(@lines) {

    my ( $not_after, $subject, $subject_altname );

    foreach my $line (@lines) {
        $not_after       = $1 if ( $line =~ /notAfter=(.*)/ );
        $subject         = $1 if ( $line =~ /subject=CN\s+=\s+(.*)/ );
        $subject_altname = $1 if ( $line =~ /(DNS:.*)/ );
    }

    my ( $empty, @san ) = split( /DNS:/, $subject_altname );    # $empty is whats before the first DNS
    s/[, ]//g for @san;                                         # remove unwanted chars
    my %uniq_subjects = map { $_, 1 } @san, $subject;           # # subject is also in altnames, so filter it out
    return $not_after, keys %uniq_subjects;
}

sub _get_local_certs($secrets) {

    my $certs = {};

    for my $e ( keys $secrets->%* ) {

        if ( $e =~ /^letsencrypt-([^.]+)[.](.+)[.]crt$/x ) {
            my ( $cert_type, $name ) = ( $1, $2 );
            my $cert = join( "\n", $secrets->{$e}->{CONTENT}->@* );
            my ( $valid_to, @domains ) = _get_cert_validity run_open("cat << \"EOF\" | openssl x509 -subject -enddate -ext subjectAltName -noout\n$cert\nEOF");

            for my $domain (@domains) {
                die "ERROR: multiple certs for domain: $domain" if exists $certs->{$domain};
                $certs->{$domain} = $valid_to;
            }
        }
    }
    return $certs;
}

sub _list_config ( $query, @args ) {

    my $secrets     = $query->('secrets');
    my $dns         = $query->('dns');
    my $letsencrypt = $query->('letsencrypt_config');
    my $ssl         = _get_local_certs($secrets);
    my $wildcards   = get_wildcards($dns);

    # list letsencrypt keys (show missing)
    print_table 'LetsEncrypt DOMAIN', 'KEY', ": KEY_ID\n";
    foreach my $root_domain ( sort keys $wildcards->%* ) {
        my $key_id = kexists( $letsencrypt, $root_domain, 'ID' ) ? $letsencrypt->{$root_domain}->{ID} : 'No';
        my $key = kexists( $letsencrypt, $root_domain, 'KEY' ) ? 'Yes' : 'No';
        print_table $root_domain, $key, ": $key_id\n";
    }

    # list certs (show missing)
    print_table 'DOMAIN', 'SUBDOMAIN', ": VALID\n";
    foreach my $root_domain ( sort keys $wildcards->%* ) {

        my $domains = $wildcards->{$root_domain};
        foreach my $domain ( sort keys $domains->%* ) {
            my $valid = exists $ssl->{$domain} ? $ssl->{$domain} : 'No';
            print_table $root_domain, $domain, ": $valid\n";
        }
    }
    return;
}

###########################################
sub import_list () {

    my $struct = {};

    $struct->{list}->{ssl} = {

        CMD  => \&_list_config,
        DESC => 'list SSL certs',
        HELP => ['lists all SSL certs and their status'],
        DATA => {
            dns                => 'state dns',
            secrets            => 'state secrets',
            letsencrypt_config => 'state letsencrypt_config'
        }
    };

    return $struct;
}

1;
