#!/usr/bin/perl
use strict;
use warnings;
use Net::Ping;

my $continue    = '/init_complete';
my $supervisord = '/usr/bin/supervisord -c [% container.config.CONTAINER.PATHS.CONFIG %]/supervisord.conf';    # supervisord complains without explicit -c
my $host        = '[% machine.self.NETWORK.INTERN.ADDRESS %]';        # docker interface
my $timeout     = 15;                                                 # less seems to cause issues under load. this equals 30s
my $interface   = '';
my $conditions  = [
    \&_init_complete,                                                 # check if the container setup has completed
    \&_get_interface,                                                 # check if the interface is there
    \&_check_interface_up,                                            # most services don't like it when the network is down
    \&_ping_host,                                                     # just to make sure...
];

# wait for docker to finish the container setup, before starting the timer
# there might be long-running PRE_INIT tasks such as liquibase.
# or heavy load due to lots of container starts
sub _init_complete {

    while (1) {
        if ( -e $continue ) {
            unlink $continue;
            return 1;
        }
        sleep 1;
    }
}

# so the container interface is not always eth0. i suspect, it is named after the one in the bridge,
# which might be any. lets focus on eth? named interfaces. any single one in up state is sufficient
sub _get_interface {

    for my $i ( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ) {
        if ( -e "/sys/class/net/eth$i/operstate" ) {
            $interface = "/sys/class/net/eth$i/operstate";
            return 1;
        }
    }
    return 0;
}

sub _check_interface_up {

    open( my $fh, '<', $interface ) or die "ERROR: opening $interface";
    my $line = readline $fh;
    close $fh or die "ERROR: closing $interface";
    chomp $line;
    return 1 if $line eq 'up';
    return 0;
}

sub _ping_host {

    my $r = 0;
    my $p = Net::Ping->new();
    $r = 1 if $p->ping( $host, 1 );
    $p->close();
    return $r;
}

sub _sleep {

    sleep 1;
    $timeout = $timeout - 1;
    return $timeout;
}

sub _wait {

    my $cond = shift;
    while (1) {
        last if $cond->();
        die 'ERROR: Timeout reached' unless _sleep();
    }
    return;
}

_wait $_ for ( $conditions->@* );
exec $supervisord;
