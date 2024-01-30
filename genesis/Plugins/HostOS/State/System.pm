package Plugins::HostOS::State::System;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::File qw(read_files);
use PSI::RunCmds qw(run_open);
use PSI::Console qw(print_table);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(get_system get_switched);

my $possible_systems = {
    system => {
        system1 => { root => 'system1' },
        system2 => { root => 'system2' }
    },
    #mtype => {
    #    #        kvm   => '0',
    #    metal => '0',
    #    vbox  => '0'
    #}
};

sub _get_chroot ( $print ) {

    print_table( 'Checking for chroot ', ' ', ': ' ) if $print;

    # i tried a lot of things. so far, it seems the internet is right
    # http://unix.stackexchange.com/questions/14345/how-do-i-tell-im-running-in-a-chroot
    my $chroot = 'yes';
    my ( $root_device_number, $root_inode ) = stat('/');
    my ( $proc_device_number, $proc_inode ) = stat('/proc/1/root/.');

    $chroot = 'no' if ( $proc_device_number && $proc_inode && $root_device_number eq $proc_device_number && $root_inode eq $proc_inode );
    say $chroot if $print;

    return $chroot;
}

sub _get_root( $print ) {

    print_table( 'Determining /', ' ', ': ' ) if $print;

    # sometimes mount does not work in chroot, so we use that
    my ( $subvol, @rest ) = run_open 'btrfs subvolume show / 2>&1 | grep Name', sub(@) { }; # btrfs fails when not used on a btrfs fs. ignore that

    if ( $subvol && $subvol =~ /\s*Name:\s+([^\s]+)/x ) {

        my $curvol = $1;
        my $tarvol = '';
        my $pos    = 0;

        foreach my $system ( keys $possible_systems->{system}->%* ) {

            if ( $possible_systems->{system}->{$system}->{root} eq $curvol ) {
                $pos = 1;
            }
            else {
                $tarvol = $possible_systems->{system}->{$system}->{root};
            }
        }

        die 'ERROR: Mounted / is not known in config' unless $pos;
        say $curvol if $print;

        return ( $curvol, $tarvol );
    }
    else {
        say 'rootfs' if $print;

        # in bootstrap, its always system1
        return ( 'system1', 'system1' );
    }
}

sub _get_release ( $release_f, $print ) {

    my $release_h = {};

    print_table( 'Reading release file ', $release_f, ': ' ) if $print;
    if ( file_exists $release_f ) {

        my $release = read_files($release_f);

        foreach ( $release->{CONTENT}->@* ) {

            if (m/^([^ ]+)[ ]([^:]+):\s*(\d+)$/x) {
                $release_h->{ join( '_', $1, $2 ) } = $3;
            }
        }
        say 'OK' if $print;
    }
    else {
        say 'Not Found' if $print;
    }
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

    # $p is {
    #fstab_file => '',
    #grub_file =>'',
    #release_file=>'',
    #};

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

    if ( $system->{chroot} eq 'yes' ) {
        $system->{target} = $current_system;
    }

    return $system;
}

1;
