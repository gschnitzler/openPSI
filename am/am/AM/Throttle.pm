#!/usr/bin/perl
package AM::Throttle;

use ModernStyle;
use Data::Dumper;
use Exporter qw(import);

use PSI::Parse::File qw(read_files);
use PSI::RunCmds qw(run_open);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(am_throttle);

#########################

my $state = {
    0 => 'down',
    1 => 'up'
};

sub _get_core_count() {

    my ($core_count) = run_open('nproc');
    return $core_count;
}

sub _get_core_utilization() {

    my $c    = read_files('/proc/loadavg');
    my $load = $c->{CONTENT}->[0];
    my ( $m1, $m5, $m15 ) = split( /\s/, $load );    # ignore the other fields

    # only interested in 1min average and there only the full core utilization
    # no need to round up or down. either a core is fully saturated, or it is not.
    $m1 =~ s/[.].+//;
    return $m1;
}

sub _threshold ( $cores, $max_percent, $manual_throttle ) {

    return sub($load) {

        return 2 if file_exists $manual_throttle;    # manual
        return 0 if $load == 0;                      # no load
        return 1 if $load >= $cores;                 # max load

        my $percent_load = $load / $cores * 100;
        $percent_load =~ s/[.].+//;                   # ignore float
                                                     # say "$percent_load%";
        return 1 if ( $max_percent < $percent_load );
        return 0;
    };
}

sub _shift_state ( $s, $a ) {

    my $state_action = $state->{$s};
    foreach my $action_name ( keys $a->%* ) {

        say "$state_action $action_name starting";
        my $action      = $a->{$action_name}->{$state_action};
        my $action_args = $a->{$action_name}->{args};
        my $retval      = $action->( $state_action, $action_args );
        say "$state_action $action_name finished (EC:$retval)";
    }
    return $s;
}

#########################

sub am_throttle($config) {

    my $sleep_interval  = $config->{global}->{sleep_interval};
    my $threshold_load  = $config->{global}->{threshold_load};
    my $manual_throttle = $config->{global}->{manual_throttle};
    my $actions         = $config->{actions};
    my $cores           = _get_core_count();
    my $threshold       = _threshold( $cores, $threshold_load, $manual_throttle );
    my $critical_state  = 0;

    die "ERROR: invalid sleep_interval: $sleep_interval" if ( $sleep_interval < 1 || $sleep_interval > 60 );
    die "ERROR: invalid threshold_load: $threshold_load" if ( $threshold_load < 1 || $threshold_load > 99 );
    die 'ERROR: threshold_load is less than one saturated core' if ( $threshold->(1) );

    say "Cores: #$cores, max_load: $threshold_load%";

    return sub() {
        while (1) {

            my $cur_load      = _get_core_utilization();
            my $critical_load = $threshold->($cur_load);

            if ( !$critical_state && $critical_load ) {
                print 'Manual override active: ' if ( $critical_load == 2 );
                say "Entering critical state: Cores: #$cores Load: $cur_load Threshold: $threshold_load%";
                $critical_state = _shift_state( 1, $actions );
            }

            if ( $critical_state && !$critical_load ) {
                say "Leaving critical state: Cores: #$cores Load: $cur_load Threshold: $threshold_load%";
                $critical_state = _shift_state( 0, $actions );
            }

            sleep $sleep_interval;
        }
        return;
    }
}
