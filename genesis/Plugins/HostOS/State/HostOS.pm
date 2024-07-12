package Plugins::HostOS::State::HostOS;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::HostOS::State::System      qw(get_system);
use Plugins::HostOS::Libs::Parse::Users qw(read_users);

our @EXPORT_OK = qw(get_hostos_state);

sub get_hostos_state ($get_system_param) {

    return {
        user   => sub (@args) { return read_users() },
        chroot => sub (@args) {
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
    };
}

