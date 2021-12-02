package Plugins::HostOS::State::HostOS;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::HostOS::State::MachineType qw(get_machine_type);
use Plugins::HostOS::State::System qw(get_system);
use Plugins::HostOS::State::User qw(get_user);

our @EXPORT_OK = qw(get_hostos_state);

sub get_hostos_state( $get_system_param ) {

    return {
        machine_type => \&get_machine_type,
        user         => \&get_user,
        chroot       => sub(@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{chroot};
        },
        root_current => sub (@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{current};
        },
        root_target => sub (@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{target};
        },
        release => sub (@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{release};
        },
        bootstrap => sub (@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{bootstrap};
        },
        possible_systems => sub (@args) {
            my $h = get_system( $get_system_param, @args );
            return $h->{possible_systems};
        },
    };

}

1;
