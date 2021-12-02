package Plugins::HostOS::Libs::Parse::Dnsmasq;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_dnsmasq);

#####################################################################

sub _gen_hosts ($config) {

    my $containers       = $config->{container};
    my $hostip           = $config->{network}->{INTERN}->{ADDRESS};
    my $ownname          = $config->{name};
    my $ownfullname      = $config->{fullname};
    my $nodes            = $config->{nodes};
    my $container_config = $config->{container_config};
    my @hosts            = ();

    push @hosts, join( ' ', '127.0.0.1', 'localhost' );    # add loopback
    push @hosts, join( ' ', $hostip, $ownname, $ownfullname );    # add myself

    foreach my $node ( keys $nodes->%* ) {                        # add nodenames

        my $ip   = $nodes->{$node}->{NETWORK}->{INTERN}->{ADDRESS};
        my $name = $nodes->{$node}->{NAMES}->{SHORT};
        push @hosts, join( ' ', $ip, $name );
    }

    foreach my $container_name ( keys $containers->%* ) {

        foreach my $container_tag ( keys $containers->{$container_name}->%* ) {

            next
              if ( !kexists( $containers, $container_name, $container_tag, 'ENABLE' )
                || $containers->{$container_name}->{$container_tag}->{ENABLE} ne 'yes' );

            my $cf = $container_config->{$container_name}->{$container_tag}->{config};
            my $ip = $cf->{NETWORK}->{IP}->{main};                                       # add the container names

            # docker kids do not allow underscores in hostnames.
            # they say they are already 12 and thus grown man, so they 'wontfix'
            my $stripped_name = $cf->{NAME} =~ s/_//gr;

            push @hosts, join( ' ', $ip, $cf->{NAME}, $stripped_name );

            # add additional names
            my @hostnames = ();
            push @hostnames, split( / /, $cf->{DNS}->{REGISTER} ) if kexists( $cf, 'DNS', 'REGISTER' );
            push @hostnames, split( / /, $cf->{DNS}->{LOCAL} )    if kexists( $cf, 'DNS', 'LOCAL' );

            foreach my $name (@hostnames) {
                push @hosts, join( ' ', $ip, $name );
            }
        }
    }
    return ( \@hosts );
}

##### frontend

sub gen_dnsmasq ($query) {

    print_table 'Generating dnsmasq cfg:', ' ', ': ';
    my $templates        = $query->('templates dnsmasq');
    my $scripts          = $query->('scripts dnsmasq');
    my $substitutions    = $query->('substitutions dnsmasq');
    my $hostsfile_config = $query->('config dnsmasq');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    $filled_templates->{'hosts'}->{CONTENT} = _gen_hosts($hostsfile_config);
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
