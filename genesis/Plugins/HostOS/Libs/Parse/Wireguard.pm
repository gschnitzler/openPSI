package Plugins::HostOS::Libs::Parse::Wireguard;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_wireguard);

###############################################################

sub _update_cfname ( $location, $name ) {
    $location =~ s/[^\/]+$//;
    return join( '', $location, $name, '.conf' );
}

sub _update_network ( $network, $ip ) {
    $network =~ s/(.*)[^.]+(\/.*)$/$1$ip$2/;
    return $network;
}

sub _update_netmask ($network) {
    $network =~ s/\/.*$/\/32/;
    return $network;
}

sub gen_wireguard ($query) {

    print_table 'Generating Wireguard:', ' ', ': ';
    my $templates        = $query->('templates wireguard');
    my $substitutions    = $query->('substitutions wireguard');
    my $config           = $query->('config wireguard wireguard');
    my $users            = $query->('config wireguard users');
    my $network          = $query->('config wireguard network');
    my $host_name        = $query->('config wireguard host_name');
    my $host_priv        = $config->{PRIV};                                                           # Interface PrivateKey
    my $host_pub         = $config->{PUB};                                                            # Interface PublicKey
    my $host_port        = $config->{PORT};                                                           # Interface ListenPort
    my $host_network     = $network->{WIREGUARD}->{NETWORK};                                          # Peer AllowedIPs
    my $host_interface   = $network->{WIREGUARD}->{INTERFACE};
    my $template         = check_and_fill_template_tree( $templates, $substitutions )->{'wg.conf'};
    my $filled_templates = { host => dclone $template };

    $filled_templates->{host}->{LOCATION} = _update_cfname( $template->{LOCATION}, $host_interface );
    push $filled_templates->{host}->{CONTENT}->@*,                                                    #
      '[Interface]',                                                                                  #
      "PrivateKey = $host_priv",                                                                      #
      "ListenPort = $host_port", '';                                                                  #

    # generate a client config for each user. essentially just swapped pub/priv keys.
    for my $user ( keys $users->%* ) {
        my $user         = $users->{$user};
        my $user_name    = $user->{NAME};
        my $user_priv    = $user->{WIREGUARD}->{PRIV};       # Peer PrivateKey
        my $user_pub     = $user->{WIREGUARD}->{PUB};        # Peer PublicKey
        my $user_address = $user->{WIREGUARD}->{ADDRESS};    # Peer PublicKey

        $filled_templates->{$user_name} = {
            CONTENT => [
                "# used for client $user_name. qrencode -t ansiutf8 < conf",
                '[Interface]',
                join( ' = ', 'PrivateKey', $user_priv ),
                join( ' = ', 'Address',    _update_network( $host_network, $user_address ) ),
                '',
                '[Peer]',
                join( ' = ', 'PublicKey',  $host_pub ),
                join( ' = ', 'AllowedIPs', '0.0.0.0/0' ),
                join( ' = ', 'Endpoint',   "$host_name:$host_port" ),

            ],
            LOCATION => _update_cfname( $template->{LOCATION}, "user.$user_name" ),
            CHMOD    => $template->{CHMOD}
        };

        push $filled_templates->{host}->{CONTENT}->@*,    #
          '[Peer]',                                       #
          join( ' = ', 'PublicKey', $user_pub ),          #
          join( ' = ', 'AllowedIPs', _update_netmask( _update_network( $host_network, $user_address ) ) ), '';
    }

    say 'OK';
    return $filled_templates;
}

1;
