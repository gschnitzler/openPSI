package Plugins::LetsEncrypt::Lib::GetWildcards;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(get_wildcards);

####################################

sub _get_domains($dns_config) {

    my $subs = {};

    foreach my $zone ( keys $dns_config->%* ) {

        my @domains = keys $dns_config->{$zone}->{A}->%*;

        #push @domains, "test.featureX.$zone";

        foreach my $domain (@domains) {
            my @parts = reverse split /[.]/, $domain;

            if ( scalar @parts > 1 ) {

                # check if the domain has known sub tlds
                # this should better be handled via a configfile.
                # until it is, be sure to also update the DNS Filter in cfgen

                # just shift off the extra subTLD part
                if ( $parts[1] eq 'co' && $parts[0] eq 'uk' ) {
                    shift @parts;
                }
                elsif ( $parts[1] eq 'com' && $parts[0] eq 'au' ) {
                    shift @parts;
                }
            }

            shift @parts;    # remove TLD
            shift @parts;    # remove domain

            #next if scalar @parts == 1;    # ignore everything that is handled by the root wildcard

            # rest are subdomains
            $subs->{$zone} = {} unless exists $subs->{$zone};
            my $pointer = $subs->{$zone};

            foreach my $part (@parts) {
                $pointer->{$part} = {} unless exists $pointer->{$part};
                $pointer = $pointer->{$part};
            }
        }
    }
    return $subs;
}

sub _get_wildcards($domains) {

    my $cond = sub ($b) {
        return 1 if ( scalar keys $b->[0]->%* != 0 );
        return;
    };

    my $wildcards = {};

    for my $e ( slice_tree $domains, $cond ) {

        my $p      = $e->[1];
        my $domain = shift $p->@*;
        my $fqdn   = join( '.', reverse( $p->@* ), $domain );

        # 0 means host only
        # 1 means wildcard
        # 2 means host & wildcard
        # since we dont know what is needed, just create both.
        # update: this is not yet implemented, and nothing uses host certs.
        # to decrease the API burden, just do wildcards
        $wildcards->{$domain}->{$fqdn} = 1;
    }

    return $wildcards;
}

####################################

sub get_wildcards ( $dns ) {

    my $subdomains = _get_domains($dns);
    my $wildcards  = _get_wildcards($subdomains);
    return $wildcards;
}
