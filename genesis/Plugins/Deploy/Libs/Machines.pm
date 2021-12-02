package Plugins::Deploy::Libs::Machines;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Console qw(read_stdin);

our @EXPORT_OK = qw(list_machines);

sub _list_same_group ($p) {

    my $mode     = $p->{mode};
    my $nodes    = $p->{nodes};
    my $mro_user = $p->{mro_user};
    my $mro_key  = $p->{mro_key};
    my $machines = {};
    my $dispatch = {
        bootstrap => sub ($node) {
            return {
                address => $node->{NETWORK}->{PUBLIC}->{ADDRESS},
                user    => 'root',
                port    => '22'
            };
        },
        normal => sub ($node) {
            return {
                address => $node->{NETWORK}->{PUBLIC}->{ADDRESS},
                port    => $node->{COMPONENTS}->{SERVICE}->{ssh}->{SSHPORT},
                keyfile => $mro_key,
                user    => $mro_user,
            };
        }
    };

    foreach my $machine ( keys $nodes->%* ) {
        $machines->{$machine} = $dispatch->{$mode}->( $nodes->{$machine} );
    }
    return $machines;
}

# adjacent machines have no interfaces (PUBLIC, INTERN, PRIVATE), instead, they only have their PUBLIC entry directly under NETWORK
sub _list_other_group ($p) {

    my $mode     = $p->{mode};
    my $nodes    = $p->{other_nodes};
    my $mro_user = $p->{mro_user};
    my $mro_key  = $p->{mro_key};
    my $machines = {};
    my $dispatch = {
        bootstrap => sub ( $node, $om ) {
            my $machine = {
                address => $node->{NETWORK}->{ADDRESS},
                user    => 'root',
                port    => '22',
                keyfile => ''
            };

            if ( kexists( $node, 'SSH', 'NAT' ) ) {
                my $override = $node->{SSH}->{NAT};
                $machine->{address} = $override->{ADDRESS}        if ( exists( $override->{ADDRESS} ) );
                $machine->{port}    = $override->{BOOTSTRAP_PORT} if ( exists( $override->{BOOTSTRAP_PORT} ) );
            }
            return $machine;
        },
        normal => sub ( $node, $om ) {
            my $machine = {
                address => $node->{NETWORK}->{ADDRESS},
                port    => $node->{SSH}->{SSHPORT},
                keyfile => $mro_key,
                user    => $mro_user,
            };

            if ( kexists( $node, 'SSH', 'NAT' ) ) {
                my $override = $node->{SSH}->{NAT};
                $machine->{address} = $override->{ADDRESS}     if ( exists( $override->{ADDRESS} ) );
                $machine->{port}    = $override->{NORMAL_PORT} if ( exists( $override->{NORMAL_PORT} ) );
            }
            return $machine;
        }
    };

    foreach my $machine_name ( keys $nodes->%* ) {

        my $other_machine;
        if ( exists( $nodes->{$machine_name} ) ) {
            $other_machine = $nodes->{$machine_name};
        }
        elsif ( exists( $nodes->{any} ) ) {
            $other_machine = $nodes->{any};
        }
        else {
            die 'ERROR: no key found';
        }

        $machines->{$machine_name} = $dispatch->{$mode}->( $nodes->{$machine_name}, $other_machine );

        # dhcp interfaces have no address, guessing the right interface in case of more than PUBLIC is also bad
        # so lets just plain ask

        if ( !$machines->{$machine_name}->{address} ) {

            say "Could not determine an address for $machine_name.";
            my $line = read_stdin( 'Enter Hostname/IP # ', -style => 'bold yellow' );

            #chomp $line;
            $line =~ s/\s//xg;
            $machines->{$machine_name}->{address} = $line;
        }
    }
    return $machines;
}

sub list_machines ( $p ) {

    # nodes in same group ignore public ssh
    return _list_same_group($p) if ( $p->{wanted_group} eq $p->{own_group} );
    return _list_other_group($p);
}
