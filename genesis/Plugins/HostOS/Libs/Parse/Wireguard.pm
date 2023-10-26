package Plugins::HostOS::Libs::Parse::Wireguard;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_wireguard);

###############################################################

sub _update_cfname ( $location, $ifname ) {

    $location =~ s/[^\/]+$//;
    return join( '', $location, $ifname, '.conf' );
}

sub _add_peers ( $users, $network ) {

    my @cf = ();
    foreach my $k ( keys $users->%* ) {
        my $user      = $users->{$k};
        my $user_name = $user->{NAME};
        my $user_pub  = $user->{WIREGUARD}->{PUB};    # Peer PublicKey
        push @cf, '',                                 #
          '[Peer]',                                   #
          join( ' = ', 'PublicKey',  $user_pub ),     #
          join( ' = ', 'AllowedIPs', $network );
    }
    return @cf;
}

sub gen_wireguard ($query) {

    print_table 'Generating Wireguard:', ' ', ': ';
    my $templates        = $query->('templates wireguard');
    my $substitutions    = $query->('substitutions wireguard');
    my $config           = $query->('config wireguard wireguard');
    my $users            = $query->('config wireguard users');
    my $network          = $query->('config wireguard network');
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    my $host_priv        = $config->{PRIV};                                              # Interface PrivateKey
    my $host_pub         = $config->{PUB};
    my $host_port        = $config->{PORT};                                              # Interface ListenPort
    my $host_network     = $network->{WIREGUARD}->{NETWORK};                             # Peer AllowedIPs
    my $host_interface   = $network->{WIREGUARD}->{INTERFACE};                           # Configname

    my $cf = $filled_templates->{'wg.conf'};
    $cf->{LOCATION} = _update_cfname( $cf->{LOCATION}, $host_interface );
    push $cf->{CONTENT}->@*, _add_peers( $users, $host_network );
    #say Dumper $filled_templates;
    say 'OK';
    return $filled_templates;
}

1;
