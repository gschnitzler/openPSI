package Plugins::HostOS::State::System;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::File  qw(read_files);
use PSI::RunCmds      qw(run_open);
use PSI::Console      qw(print_table);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(get_system get_switched);

my $possible_systems = {
    system => {
        system1 => { root => 'system1' },
        system2 => { root => 'system2' }
    },
};

sub _get_chroot ($print) {

    print_table( 'Checking for chroot ', ' ', ': ' ) if $print;

    # i tried a lot of things. so far, it seems the internet is right
    # http://unix.stackexchange.com/questions/14345/how-do-i-tell-im-running-in-a-chroot
    my ( $root_device_number, $root_inode ) = stat('/');
    my ( $proc_device_number, $proc_inode ) = stat('/proc/1/root/.');
    my $chroot = 'yes';
    $chroot = 'no' if ( $proc_device_number && $proc_inode && $root_device_number eq $proc_device_number && $root_inode eq $proc_inode );
    say $chroot if $print;

    return $chroot;
}

sub _get_root ($print) {

    print_table( 'Determining /', ' ', ': ' ) if $print;

    # sometimes mount does not work in chroot, so we use that
    my ( $subvol, @rest ) = run_open 'btrfs subvolume show / 2>&1 | grep Name', sub(@) { };    # btrfs fails when not used on a btrfs fs. ignore that

    if ( $subvol && $subvol =~ /\s*Name:\s+([^\s]+)/x ) {

        my $current_volume = $1;
        my $target_volume  = '';
        my $pos            = 0;

        foreach my $system ( keys $possible_systems->{system}->%* ) {

            if ( $possible_systems->{system}->{$system}->{root} eq $current_volume ) {
                $pos = 1;
                next;
            }
            $target_volume = $possible_systems->{system}->{$system}->{root};
        }

        die 'ERROR: Mounted / is not known in config' unless $pos;
        say $current_volume if $print;

        return ( $current_volume, $target_volume );
    }

    say 'rootfs' if $print;
    return ( 'system1', 'system1' );    # in bootstrap, its always system1
}

sub _get_release ( $release_f, $print ) {

    print_table( 'Reading release file ', $release_f, ': ' ) if $print;
    my $release_h = {};

    if ( !file_exists $release_f ) {
        say 'Not Found' if $print;
        return $release_h;
    }

    foreach ( read_files($release_f)->{CONTENT}->@* ) {
        if (m/^([^ ]+)[ ]([^:]+):\s*(\d+)$/x) {
            $release_h->{ join( '_', $1, $2 ) } = $3;
        }
    }

    say 'OK' if $print;    # when the match did not work, the result is the same as 'Not Found', but the printed 'OK' is misleading
    return $release_h;
}

# this is just that. verify that we use hostos
# keep in mind, that in chroot environments, after os_base is build and used, the chroot system is not considered bootstrap.
# also, the concept of 'bootstrap mode' is somewhat misleading. its a relic from old days and might be the wrong concept to cling to.
# consider renaming it to prevent confusion.
sub _get_bootstrap ( $system, $print ) {    #

    my $ret = 'yes';
    $ret = 'no' if ( scalar keys $system->{release}->%* );
    return $ret;
}

#################################

sub get_system ( $p, $print = 0 ) {

    $print = 1 if $print eq 'print';
    my $release_file = $p->{release_file};
    my ( $current_system, $target_system ) = _get_root($print);
    my $system = {
        current          => $current_system,
        target           => $target_system,
        chroot           => _get_chroot($print),
        release          => _get_release( $release_file, $print ),
        possible_systems => $possible_systems,
    };
    $system->{bootstrap} = _get_bootstrap( $system, $print );

    # _get_root returns the root system of the currently used /
    # in chroot, the current system is actually the target system.
    # why is that?
    if ( $system->{chroot} eq 'yes' ) {
        $system->{target} = $current_system;
    }

    return $system;
}

1;
