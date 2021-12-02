package Plugins::HostOS::Libs::Parse::Network;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);
use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(gen_network);

#####################################################################

# sub _parse_arptables {

#     my $arptables = shift;
#     my $parsed    = {};
#     my $table     = '';

#     foreach my $line ( $arptables->@* ) {

#         $line =~ s/#.*//x;
#         $line =~ s/^\s*//x;

#         if ( $line =~ /^\*(.*)/x ) {
#             my $t = $1;
#             die 'ERROR: new table $t encountered without prior commit' if ($table);
#             $table = $t;
#         }

#         # unlike iptables, there is only one table, and no commit statement
#         next unless $table;

#         if ( $line =~ /^:(.*)/x ) {
#             my $chain = $1;
#             die 'ERROR: new chain $chain encountered without table' unless ($table);
#             push $parsed->{$table}->{chains}->@*, $chain;
#         }
#         elsif ( $line =~ /.*-A\ .+\ -j\ /x ) {
#             push $parsed->{$table}->{rules}->@*, $line;
#         }
#     }
#     die 'ERROR: Table filter not found in template' unless ( exists( $parsed->{filter} ) );
#     return $parsed;
# }

# sub _create_arptables {

#     my $arp  = shift;
#     my @file = ();

#     foreach my $table_name ( keys( $arp->%* ) ) {

#         my $table = $arp->{$table_name};
#         push @file, "*$table_name";

#         foreach my $c ( $table->{chains}->@* ) {
#             push @file, join( '', ':', $c );
#         }

#         push @file, $table->{rules}->@*;
#     }

#     return \@file;
# }

# sub _generate_arptables {

#     my ( $template, $config ) = @_;
#     my $networks         = $config->{state}->{network};
#     my $public_interface = $networks->{PUBLIC}->{INTERFACE};

#     my $ipsec_config = $config->{cluster}->{self}->{SERVICE}->{IPSEC};

#     #  my $roadwarrior_interface = $ipsec_config->{INTERFACE};
#     #  my $roadwarrior_base      = $ipsec_config->{POOL}->{START};
#     #  my $roadwarrior_size      = $ipsec_config->{POOL}->{SIZE};

#     my $arptables = _parse_arptables($template);
#     my $f_rules   = $arptables->{filter}->{rules};

#     # standard rules
#     foreach my $network_name ( keys( $networks->%* ) ) {

#         my $network    = $networks->{$network_name};
#         my $dhcp       = $network->{DHCP};
#         my $interface  = $network->{INTERFACE};
#         my $ip_network = $network->{NETWORK};
#         my $ip_address = $network->{ADDRESS};
#         my $additional = $network->{ADDITIONAL};

#         # interfaces using dhcp are allowed to accpet all arp packets. so make sure pvlan is disabled for that interface in the arptables init script,
#         # or the machine will wreak havoc in the network - you have been warned.

#         if ( $dhcp && $dhcp eq 'yes' ) {

#             push $f_rules->@*,

#                 # allow each interfaces address
#                 "-A INPUT -j ACCEPT -i $interface";
#         }
#         else {

#             push $f_rules->@*,

#                 # allow each interfaces address
#                 "-A INPUT -j ACCEPT -i $interface -d $ip_address";
#         }

#         # allow each interfaces additional ips
#         foreach my $add_name ( keys( $additional->%* ) ) {
#             my $additional_ip        = $additional->{$add_name}->{ADDRESS};
#             my $additional_interface = $additional->{$add_name}->{INTERFACE};

#             push $f_rules->@*,

#                 # allow each interfaces address
#                 "-A INPUT -j ACCEPT -i $additional_interface -d $additional_ip";
#         }
#     }

#     # ipsec rules
#     #   my @client_ips = _get_roadwarrior_range( $roadwarrior_base, $roadwarrior_size );
#     #   foreach my $client (@client_ips) {
#     #       push $f_rules->@*, "-A ipsec -j ACCEPT -i $roadwarrior_interface -d $client";
#     #
#     #   }

#     return ( _create_arptables($arptables) );

# }

# sub _get_roadwarrior_range ( $start, $size ) {

#     my @list = ();

#     if ( $start =~ m/(.*)\.([^.]+)$/x ) {
#         my ( $network, $base ) = ( $1, $2 );
#         while ( $size != 0 ) {

#             push @list, join( '.', $network, $base );
#             $base++;
#             $size--;
#         }
#     }
#     else {
#         die 'ERROR: parser error';
#     }

#     return @list;
# }

sub _get_network ( $interface, $config ) {

    my $cond = sub ($branch) {
        my $bt = $branch->[0];
        return unless ( ref $bt eq 'HASH' );
        return 1 if ( exists( $bt->{INTERFACE} ) && $bt->{INTERFACE} eq $interface );
        return;
    };

    my @match = slice_tree( $config, $cond );
    die "ERROR: network config for interface $interface not found" unless scalar @match;

    return $match[0]->[0];
}

sub _generate_interfaces ($config) {

    my $networks = $config->{state}->{network};

    my @interfaces = ();

    foreach my $key ( keys $networks->%* ) {

        my $interface = $networks->{$key}->{INTERFACE};

        # the interface init.d symlink
        push @interfaces,
          {
            LOCATION => "/etc/init.d/net.$interface",
            SYMLINK  => '/etc/init.d/net.lo',
            CHMOD    => '777',
            CONTENT  => [],
          };

        # the rc-update symlink
        push @interfaces,
          {
            LOCATION => "/etc/runlevels/default/net.$interface",
            SYMLINK  => "/etc/init.d/net.$interface",
            CHMOD    => '777',
            CONTENT  => [],
          };
    }

    return @interfaces;
}

sub _generate_network ( $template, $config ) {

    my $networks = $config->{state}->{network};

    my @content = ();

    foreach my $key ( keys $networks->%* ) {

        my $network   = $networks->{$key};
        my $interface = $network->{INTERFACE};
        my $address   = $network->{ADDRESS};
        my $netmask   = $network->{NETMASK};
        my $bcast     = $network->{BROADCAST};

        # the newline in config is intentional. this format is used for multiple IPs
        if ( exists $network->{DHCP} && $network->{DHCP} eq 'yes' ) {
            push @content, join( '', 'config_', $interface, '="dhcp"' );
        }
        else {
            push @content, join( '', 'config_', $interface, '="', $address, '/', $netmask, ' brd ', $bcast );
            foreach my $k ( keys $network->{ADDITIONAL}->%* ) {

                my $additional  = $network->{ADDITIONAL}->{$k};
                my $add_address = $additional->{ADDRESS};
                my $add_bcast   = $additional->{BROADCAST};
                my $add_netmask = $additional->{NETMASK};
                push @content, join( '', $add_address, '/', $add_netmask, ' brd ', $add_bcast );

            }
            push @content, '"';
        }
    }

    my $dns_name         = $config->{domainname};
    my $intern_interface = $networks->{INTERN}->{INTERFACE};
    my $public_interface = $networks->{PUBLIC}->{INTERFACE};
    my $public_router    = $networks->{PUBLIC}->{ROUTER};

    # dont set up a default route if we are using DHCP
    if ( !kexists( $networks, 'PUBLIC', 'DHCP' ) || $networks->{PUBLIC}->{DHCP} ne 'yes' ) {
        my $extra_route = '';
        if ( kexists( $networks, 'PUBLIC', 'EXTRA_ROUTE' ) ) {
            $extra_route = $networks->{PUBLIC}->{EXTRA_ROUTE};
            $extra_route = "\n$extra_route";
        }
        push @content, join( '', 'routes_', $public_interface, '="default via ', $public_router, $extra_route, '"' );
    }

    # upstream changed config systax https://wiki.gentoo.org/wiki/Netifrc/Brctl_Migration
    #push @content, join( '', 'brctl_',  $intern_interface, '="setfd 0 sethello 10 stp off"' );
    push @content, join( '', 'bridge_forward_delay_', $intern_interface, '=0' );
    push @content, join( '', 'bridge_hello_time_',    $intern_interface, '=1000' );
    push @content, join( '', 'bridge_stp_state_',     $intern_interface, '=0 # stp off' );
    push @content, join( '', 'bridge_',               $intern_interface, '=""' );
    push @content, join( '', 'dns_domain_lo="',       $dns_name,         '"' );

    return \@content;

}

sub _parse_iptables ($iptables) {

    my $parsed = {};
    my $table  = '';

    foreach my $line ( $iptables->@* ) {

        $line =~ s/#.*//x;
        $line =~ s/^\s*//x;

        if ( $line =~ /^[*](.*)/x ) {
            my $t = $1;
            die "ERROR: new table $t encountered without prior commit" if ($table);
            $table = $t;
        }
        elsif ( $line =~ /^:(.*)/x ) {
            my $chain = $1;
            die "ERROR: new chain $chain encountered without table" unless ($table);
            push $parsed->{$table}->{chains}->@*, $chain;
        }
        elsif ( $line =~ /^COMMIT/x ) {
            die 'ERROR: COMMIT without table' unless ($table);
            $table = '';

        }
        elsif ( $line =~ /.*-A[ ].+[ ]-j[ ]/x ) {
            push $parsed->{$table}->{rules}->@*, $line;
        }
    }
    die 'ERROR: Tables nat and filter not found in template' if ( !exists( $parsed->{filter} ) || !exists( $parsed->{nat} ) );
    return $parsed;
}

sub _create_iptables ($ipt) {

    my @file = ();

    foreach my $table_name ( keys( $ipt->%* ) ) {

        my $table = $ipt->{$table_name};
        push @file, "*$table_name";
        foreach my $c ( $table->{chains}->@* ) {
            push @file, join( '', ':', $c );
        }
        push @file, $table->{rules}->@*;
        push @file, 'COMMIT', '';

    }

    return \@file;
}

sub _generate_iptables ( $template, $config ) {

    my $networks         = $config->{state}->{network};
    my $services         = $config->{services};
    my $public_interface = $networks->{PUBLIC}->{INTERFACE};
    my $intern_interface = $networks->{INTERN}->{INTERFACE};

    my $iptables = _parse_iptables($template);
    my $f_rules  = $iptables->{filter}->{rules};
    my $n_rules  = $iptables->{nat}->{rules};

    ### standard rules
    foreach my $network_name ( keys( $networks->%* ) ) {

        my $network    = $networks->{$network_name};
        my $interface  = $network->{INTERFACE};
        my $ip_network = $network->{NETWORK};

        push $f_rules->@*, "# Standard rules for $interface";

        push $f_rules->@*,

          # local connection tracking. RELATED and ESTABLISHED connection rule is already in the template
          "[0:0] -A input_hooks -i $interface -p udp -m conntrack --ctstate NEW -j input_UDP",
          "[0:0] -A input_hooks -i $interface -p tcp --syn -m conntrack --ctstate NEW -j input_TCP";

        push $f_rules->@*,

          # forward connection tracking
          "[0:0] -A forward_hooks -i $interface -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT";

        push $f_rules->@*,

          # accept any connection coming from non-public
          "[0:0] -A forward_hooks -i $interface -s $ip_network -j ACCEPT" if ( $network_name ne 'PUBLIC' );

        push $f_rules->@*,

          # local connection tracking. RELATED and ESTABLISHED connection rule is already in the template
          "[0:0] -A forward_hooks -i $interface -p udp -m conntrack --ctstate NEW -j forward_UDP",
          "[0:0] -A forward_hooks -i $interface -p tcp --syn -m conntrack --ctstate NEW -j forward_TCP";

        push $n_rules->@*,

  # masquerading traffic
  # do not masquerade any traffic going 'public' that is destined for internal networks (! -d $ip_network), otherwise strongswan wont do its magic
  # i don't know if there is a scenario where one internal network would talk to another internal network via the external interface because of ipsec
  # in that case, multiple $ip_network would have to be exempt in the ! -d clause...
  # also in the previous hardcoded setup, for INTERN the clause was ! -d 10.0.0.0/8 ... not sure if this was a hack, or traffic from other nodes was the reason.
  #
  # the 10.0.0.0/8 is a hack, would be better to have all the node networks exempt
          "[0:0] -A POSTROUTING -o $public_interface -s $ip_network  ! -d 10.0.0.0/8 -j MASQUERADE" unless ( $network_name eq 'PUBLIC' );

        push $f_rules->@*,

          # this should only apply to PUBLIC, should be triggert by a LISTEN setting in the IPSEC SERVICE config
          "[0:0] -A input_hooks -i $interface -p esp -m conntrack --ctstate NEW -j ACCEPT"
          if ( $network_name eq 'PUBLIC' );

        push $f_rules->@*,

          # ICMP types accepted on any interface
          "[0:0] -A input_hooks -i $interface -p icmp -m icmp --icmp-type 0 -m conntrack --ctstate NEW -j ACCEPT",
          "[0:0] -A input_hooks -i $interface -p icmp -m icmp --icmp-type 3 -m conntrack --ctstate NEW -j ACCEPT",
          "[0:0] -A input_hooks -i $interface -p icmp -m icmp --icmp-type 5 -m conntrack --ctstate NEW -j ACCEPT",
          "[0:0] -A input_hooks -i $interface -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT",
          "[0:0] -A input_hooks -i $interface -p icmp -m icmp --icmp-type 11 -m conntrack --ctstate NEW -j ACCEPT";

        push $f_rules->@*, '';
    }

    ### per service rules

    my $service_dispatch = {
        strongswan => sub ($service) {

            my $vpn_interface = $service->{INTERFACE};
            my $used_network  = _get_network( $vpn_interface, $networks );
            my $un_address    = $used_network->{ADDRESS};
            my $un_network    = $used_network->{NETWORK};

            push $f_rules->@*,
              '# IPSEC',
              "[0:0] -A input_UDP -i $public_interface -p udp -m udp --dport 4500 -j ACCEPT",
              "[0:0] -A input_UDP -i $public_interface -p udp -m udp --dport 500 -j ACCEPT",
              '# DHCP for IPSEC roadwarriors',
              '# allow the answer of the dhcp server',
              "[0:0] -A input_UDP -i $vpn_interface -p udp -m udp --sport 67 --dport 68 -j ACCEPT",
              '# DNS for IPSEC roadwarriors (comes from public interface)',
              "[0:0] -A input_UDP -i $public_interface -s $un_network -d $un_address -p udp -m udp --dport 53 -j ACCEPT",
              "[0:0] -A input_TCP -i $public_interface -s $un_network -d $un_address -p tcp -m tcp --dport 53 -j ACCEPT",
              '';

            # setup rules for roadwarriors
            #    my $roadwarrior_interface = $service->{POOL}->{INTERFACE};
            #    my $roadwarrior_base      = $service->{POOL}->{START};
            #    my $roadwarrior_size      = $service->{POOL}->{SIZE};

            #    my @client_ips = _get_roadwarrior_range( $roadwarrior_base, $roadwarrior_size );

            #   foreach my $client (@client_ips) {
            #       push $f_rules->@*, "[0:0] -A vpn_road -d $client -i $roadwarrior_interface -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT";
            #       push $f_rules->@*, "[0:0] -A vpn_road -s $client -i $public_interface -j ACCEPT";

            #   }

            return;

        },
        syslog => sub ($service) {

            return if ( !exists( $service->{ENABLE} ) || $service->{ENABLE} ne 'yes' );

            # SYSLOGPORT is mandatory, but MONITOR might not be configured, to disable centralized logging
            # all we want to do here, is enable the hosts syslog to receive syslog messages from the container syslogs, via INTERN interface
            my $monitor    = $service->{MONITOR};
            my $syslogport = $service->{SYSLOGPORT};
            die 'ERROR: no SYSLOGPORT configured' unless $syslogport;

            push $f_rules->@*, '# SYSLOG', "[0:0] -A input_TCP -i $intern_interface -p tcp -m tcp --dport $syslogport -j ACCEPT", '';
            return;
        },
        ssh => sub ($service) {
            my $sshport = $service->{SSHPORT};
            push $f_rules->@*, '# SSH', "[0:0] -A input_TCP -p tcp -m tcp --dport $sshport -j ACCEPT", '';
            return;
        },
        prometheus => sub ($service) {
            return if ( !exists( $service->{ENABLE} ) || $service->{ENABLE} ne 'yes' );
            my $intern_address = $networks->{INTERN}->{ADDRESS};

          # there is currently no facility to only allow specific containers access to the host.
          # so all containers on every node can now access its hosts metrics.
          # the 'INTERN' network is basically a LAN hidden behind the host as a gateway. extended by ipsec.
          # course of action would be to seperate the INTERN network into zones.
          # this would allow for fine grained ipsec networking.
          # which in turn would allow the prometheus node_exporter to be connected via ipsec to the monitor, without an all-access backdoor through the monitor.
          # which would be way better than to hide the node_exporter behind 2 http proxies.
            push $f_rules->@*, '# PROMETHEUS', "[0:0] -A input_TCP -i $intern_interface -d $intern_address -p tcp -m tcp --dport 9100 -j ACCEPT", '';
            return;
        },
        csync => sub ($service) {
            return if ( !exists( $service->{ENABLE} ) || $service->{ENABLE} ne 'yes' );
            my $intern_address = $networks->{INTERN}->{ADDRESS};

            # csync2 via ipsec
            # the connect is directed to a real host interface (docker0 ip) and thus actually leaving the tunnel on the remote (this) side via eth0
            # not sure how to counter this. could be handled with tricky racoon config, more tricky kernel sysctl and policy routing magic,
            # or by stuffing csync and lsyncd into a container.
            # none of the options is trivial.. so here is the quick and dirty fix...: just allow ipsec connects from eth0
            # there is something wrong with this... no interface specified... check this
            push $f_rules->@*, '# CSYNC', "[0:0] -A input_TCP -p tcp -m tcp -d $intern_address --dport 30865 -j ACCEPT", '';

            return;
        },
        dhcp => sub ($service) {
            return if ( !exists( $service->{ENABLE} ) || $service->{ENABLE} ne 'yes' );
            my $allowed_interface = $service->{INTERFACE};
            push $f_rules->@*, '# DHCP server', "[0:0] -A input_UDP -i $allowed_interface -p udp -m udp --sport 68 --dport 67 -j ACCEPT", '';

            # dnsmasq DNS for dhcp interface, note that $allowed_interface might be the same as $intern_interface
            # so you might see the same rule twice in the actual host iptables.
            push $f_rules->@*, '# DNSMASQ for DHCP interface',
              "[0:0] -A input_UDP -i $allowed_interface -p udp -m udp --dport 53 -j ACCEPT",
              "[0:0] -A input_TCP -i $allowed_interface -p tcp -m tcp --dport 53 -j ACCEPT", '';

            foreach my $host_name ( keys $service->{HOSTS}->%* ) {

                my $host = $service->{HOSTS}->{$host_name};

                next unless exists( $host->{NAT} );

                my $host_ip = $host->{IP};

                foreach my $nat_name ( keys $host->{NAT}->%* ) {

                    my $nat_rule         = $host->{NAT}->{$nat_name};
                    my $source           = $nat_rule->{SOURCE};
                    my $source_interface = $nat_rule->{SOURCE_INTERFACE};
                    my $port             = $nat_rule->{PORT};
                    my $nat_port         = $nat_rule->{NAT_PORT};
                    my @protos           = split( /\//, $nat_rule->{PROTO} );

                    push $f_rules->@*, "# DHCP client $host_name rule $nat_name";
                    push $n_rules->@*, "# DHCP client $host_name rule $nat_name";

                    foreach my $proto (@protos) {

                        my $chain_name = '';
                        $chain_name = 'forward_UDP' if ( $proto eq 'udp' );
                        $chain_name = 'forward_TCP' if ( $proto eq 'tcp' );
                        die "ERROR: protocol $proto does not have a chain assigned" unless ($chain_name);

                        push $f_rules->@*, "[0:0] -A $chain_name -i $source_interface -s $source -p $proto -m $proto --dport $nat_port -j ACCEPT";
                        push $n_rules->@*,
                          "[0:0] -A PREROUTING -i $source_interface -p $proto -m $proto -s $source --dport $port -j DNAT --to-destination $host_ip:$nat_port";

                    }
                    push $f_rules->@*, '';
                    push $n_rules->@*, '';
                }

            }

            return;
        },
    };

    # dnsmasq DNS for docker
    push $f_rules->@*, '# DNSMASQ for docker',
      "[0:0] -A input_UDP -i $intern_interface -p udp -m udp --dport 53 -j ACCEPT",
      "[0:0] -A input_TCP -i $intern_interface -p tcp -m tcp --dport 53 -j ACCEPT", '';

    foreach my $service_name ( keys $services->%* ) {

        next unless $services->{$service_name}->{ENABLE} eq 'yes';
        $service_dispatch->{$service_name}->( $services->{$service_name} ) if exists $service_dispatch->{$service_name};

    }

    return ( _create_iptables($iptables) );
}

##### frontend

sub gen_network ($query) {

    print_table 'Generating net config:', ' ', ': ';
    my $templates        = $query->('templates network');
    my $substitutions    = $query->('substitutions network');
    my @cf               = ();
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );

    # $template->{CONTENT} = _generate_arptables( $template->{CONTENT}, $substitutions ) if ( $template eq 'arptables' );
    $filled_templates->{iptables}->{CONTENT} = _generate_iptables( $filled_templates->{iptables}->{CONTENT}, $substitutions );
    $filled_templates->{network}->{CONTENT}  = _generate_network( $filled_templates->{network}, $substitutions );
    push @cf, _generate_interfaces($substitutions);
    say 'OK';
    return $filled_templates, @cf;
}

1;
