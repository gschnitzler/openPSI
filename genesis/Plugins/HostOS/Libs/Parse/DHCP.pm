package Plugins::HostOS::Libs::Parse::DHCP;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console         qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_dhcp);

#####################################################################

sub _gen_dhcp ( $content, $config ) {

    my $ifname = $config->{INTERFACE};
    my $start  = $config->{START};
    my $end    = $config->{END};
    my $lease  = $config->{LEASE};
    my $hosts  = $config->{HOSTS};
    my $router = $config->{ROUTER};
    my $option = exists $config->{OPTION} ? $config->{OPTION} : '';

    my @add = ();

    #dhcp-authoritative
    #dhcp-range=eth1,192.168.111.100,192.168.111.149,48h
    #dhcp-option=option:router,192.168.111.11
    #dhcp-host=kouch,192.168.111.30
    #dhcp-host=00:A0:DE:A3:7E:27,yamaha,192.168.111.29

    push @add, 'dhcp-authoritative',                                              #
      join( '', 'dhcp-range=', $ifname, ',', $start, ',', $end, ',', $lease ),    #
      join( '', 'dhcp-option=option:router,', $router ), #
      '';   #   newline

    push @add, join( '', 'dhcp-option=', $option ) if $option;

    foreach my $host_name ( sort keys $hosts->%* ) {

        my $host = $hosts->{$host_name};
        my @line = ();

        if ( exists( $host->{MAC} ) ) {
            push @line, $host->{MAC};
        }

        if ( exists $host->{TAG} ) {
            push @line, $host->{TAG};
        }

        push @line, join( '', $host_name ), $host->{IP};
        push @add, join( '', 'dhcp-host=', join( ',', @line ) );
    }

    push( $content->@*, @add );
    return $content;
}

################################################################

sub gen_dhcp ($query) {

    # lookup of hostnames of dhcp clients only works on active leases. so names need to also be added to /etc/hosts.
    # which is done in dnsmasq plugin

    print_table 'Generating dhcp cfg:', ' ', ': ';
    my $templates        = $query->('templates dhcp');
    my $scripts          = $query->('scripts dhcp');
    my $substitutions    = $query->('substitutions dhcp');
    my $config           = $query->('config dhcp dhcp');
    my $filled_scripts   = check_and_fill_template_tree( $scripts,   $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    $filled_templates->{'dnsmasq.dhcp.conf'}->{CONTENT} = _gen_dhcp( $filled_templates->{'dnsmasq.dhcp.conf'}->{CONTENT}, $config );
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
