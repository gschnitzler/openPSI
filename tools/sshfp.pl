#!/usr/bin/perl
#
# cpanm MojoX::CloudFlare::Simple
# CloudFlare::Client is obsolete

use lib '/data/psi/Libs';
use lib '/data/psi/cfgen';
use ModernStyle;
use Data::Dumper;
use MojoX::CloudFlare::Simple;

use IO::Config::Read qw(read_config_single load_config);
die 'ERROR: this was written for old secrets mount. adapt it to use pass';

my $config_path  = '/data/psi/config/Cluster/';
my $secrets_path = '/data/psi/secrets';
my $domains      = {
    'domain.xyz' => {
        API_KEY_PATH => "$secrets_path/global.cloudflare.api.domain",
        USER         => 'c@d.com',
    },
    'dom.com' => {
        API_KEY_PATH => "$secrets_path/global.cloudflare.api.dom",
        USER         => 'a@b.com',
    }
};


#############################################################
#
# Well, it was all fun and games, but futile in the end. cloudflare does not support SSHFP records
# on the plus side, this can now serve as a demo.
#
##############################################################

sub _read_config($path) {

    my $cluster = load_config( read_config_single( 0, $path ) );
    my @machines = ();

    for my $cluster_name ( keys $cluster->%* ) {

        my $machine_path = join( '/', $path, $cluster_name );
        push @machines, load_config( read_config_single( 0, $machine_path ) );
    }
    return \@machines;
}

sub _add_api_keys($hash) {

    for my $k ( keys( $hash->%* ) ) {

        my $path = $hash->{$k}->{API_KEY_PATH};
        open( my $fh, '<', $path ) or die "could not open $path";
        my $apikey = readline($fh);
        close($fh);
        chomp $apikey;
        $hash->{$k}->{API_KEY} = $apikey;
    }
}

sub _add_domain_todo ( $domain_cf, $machines ) {

    for my $m ( $machines->@* ) {

        for my $k ( keys $m->%* ) {
            my $machine   = $m->{$k};
            my $priv_path = $machine->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB};
            my $fqdn      = $machine->{NAMES}->{FULL};

            $priv_path =~ s/SECRETS://;
            $priv_path = join( '/', $secrets_path, $priv_path );

            open( my $keygen, '-|', "ssh-keygen -r $fqdn -f $priv_path" ) or die "could not open $priv_path in keygen";
            my @dns_entries = <$keygen>;
            close $keygen;

            chomp for @dns_entries;

            #say "$fqdn $priv_path";
            my $domain = $1 if ( $fqdn =~ /\.([^.]+\.[^.]+)$/ );

            die 'ERROR: unknown domain $domain' unless ( exists $domain_cf->{$domain} );

            my $todo_machine = {
                fqdn => $fqdn,
                dns  => \@dns_entries,
            };

            foreach my $k ( keys $todo_machine->%* ) {
                my $tmk = $todo_machine->{$k};
                die 'not enough dns entries' if ( ref $tmk eq 'ARRAY' && scalar $tmk->@* != 2 );
                die 'empty entry $k' if ( !ref $tmk && !defined $tmk );
            }

            push $domain_cf->{$domain}->{TODO}->@*, $todo_machine;
        }
    }
}

sub _add_zoneid ( $cf, $d ) {

    my $zones = $cf->request( 'GET', "zones" );

    foreach my $zone_entry ( $zones->{result}->@* ) {
        my $ze_domain = $zone_entry->{name};
        my $ze_id     = $zone_entry->{id};
        say "Adding Zone ID $ze_domain:$ze_id";
        $d->{$ze_domain}->{ZONEID} = $ze_id;
    }
    return;
}

sub _delete_sshfp_records ( $cf, $zoneid ) {

    my $sshfp_records = $cf->request( 'GET', "zones/$zoneid/dns_records", { type => 'SSHFP' } );
    foreach my $record ( $sshfp_records->{result}->@* ) {

        my $r_id = $record->{id};
        say "Deleting SSHFP record $zoneid:$r_id";
        $cf->request( 'DELETE', "zones/$zoneid/dns_records/$r_id" );
    }

    return;
}

sub _add_sshfp_records ( $cf, $zoneid, $entries ) {

    #say Dumper $entries-;
    foreach my $record ( $entries->{dns}->@* ) {

        say "Adding SSHFP record $zoneid:$entries->{fqdn} $record";
        my $result = $cf->request(
            'POST',
            "zones/$zoneid/dns_records",
            {    #
                type    => 'SSHFP',
                name    => $entries->{fqdn},
                content => $record,

            }
        );
        say Dumper $result;
    }

    return;
}

#####################################

_add_api_keys($domains);
_add_domain_todo( $domains, _read_config($config_path) );

say Dumper $domains;
exit;
foreach my $zone ( keys $domains->%* ) {

    my $cf         = $domains->{$zone};
    my $cloudflare = MojoX::CloudFlare::Simple->new(
        email => $cf->{USER},
        key   => $cf->{API_KEY},
    );

    foreach my $e ( $cf->{TODO}->@* ) {

        _add_zoneid( $cloudflare, $domains ) if ( !exists $cf->{ZONEID} );
        die 'ERROR: could not find id for $zone' if ( !exists $cf->{ZONEID} );

        _delete_sshfp_records( $cloudflare, $cf->{ZONEID} );
        _add_sshfp_records( $cloudflare, $cf->{ZONEID}, $e );

        exit 0;

    }
}



