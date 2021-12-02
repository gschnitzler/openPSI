package Config::Throttle;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(throttle_config);

#########################


#################
# old stuff

sub __handler ( $action, $args ) {

    my $cf         = $args->{sshd_cf};
    my $bin        = $args->{sshd_bin};
    my $up         = $args->{up_port};
    my $dp         = $args->{down_port};
    my $hup_string = join( ' ', 'kill -HUP $(ps x | grep', $bin, '| grep -v grep | awk \'{print $1}\')' );
    my $actions    = {
        up => sub ( $cf, $hs, $up, $dp ) {
            my $mod_string = join( '', 'sed -i \'s/^Port .*/Port ', "$up/' ", $cf );
            system($mod_string) == 0 or return $?;
            system($hs) == 0         or return $?;
            return 0;
        },
        down => sub ( $cf, $hs, $up, $dp ) {
            my $mod_string = join( '', 'sed -i \'s/^Port .*/Port ', "$dp/' ", $cf );
            system($mod_string) == 0 or return $?;
            system($hs) == 0         or return $?;
            return 0;
        }
    };

    return $actions->{$action}->( $cf, $hup_string, $up, $dp ) if ( exists $actions->{$action} );
    return 1;    # do not return undef here
}

sub throttler_config () {
my $c
    return {
        global => {
            sleep_interval  => 1,                  # seconds to sleep between each loop. unsigned int between 1 and 60
            threshold_load  => 80,                 # trigger at this system load, in percent. 1-99, but its minimum must not be less than one fully loaded core
            manual_throttle => '/tmp/throttle',    # if this file exists, critical state is entered until the file is removed

        },
        actions => {
            shift_sshd_port => {                   # name
                up   => \&_handler,                # must be a code ref
                down => \&_handler,                # must be a code ref
                args => {                          # additional arguments passed to the handler

                    # well, modifying the generated config is bad, but i dont see much harm here
                    sshd_bin  => '/usr/sbin/sshd',
                    sshd_cf   => $c->{sshd}->{sshd_cf},
                    down_port => $c->{sshd}->{down_port},
                    up_port   => '1000',

                },
            },
        }
    };
}


###################


# example handler
sub _handler ( $action, $args ) {

    say 'it works!';
    return 0;    # do not return undef here
}

#########################
# Demo implementation
sub throttle_config () {

    return {
        global => {
            sleep_interval  => 1,                  # seconds to sleep between each loop. unsigned int between 1 and 60
            threshold_load  => 50,                 # trigger at this system load, in percent. 1-99, but its minimum must not be less than one fully loaded core
            manual_throttle => '/tmp/throttle',    # if this file exists, critical state is entered until the file is removed
        },
        actions => {
            'a1' => {                              # name
                up   => \&_handler,                # must be a code ref
                down => \&_handler,                # must be a code ref
                args => {},                        # additional arguments passed to the handler
            },
            'a2' => {
                up   => \&_handler,                # must be a code ref
                down => \&_handler,                # must be a code ref
                args => {},                        # additional arguments passed to the handler
            },
            'a3' => {
                up   => \&_handler,                # must be a code ref
                down => \&_handler,                # must be a code ref
                args => {},                        # additional arguments passed to the handler
            }
        }
    };
}
1;
