package Plugins::HostOS::State::System;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::File  qw(read_files);
use PSI::RunCmds      qw(run_open);
use PSI::Console      qw(print_table);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(get_system get_switched);

# there used to be various platforms with different root file systems and such.
my $possible_systems = {
    system1 => 1,
    system2 => 1,
};

sub _get_root ($print) {

    print_table( 'Determining /', ' ', ': ' ) if $print;

    # sometimes mount does not work in chroot, so we use that
    my ( $subvol, @rest ) = run_open 'btrfs subvolume show / 2>&1 | grep Name', sub(@) { };    # btrfs fails when not used on a btrfs fs. ignore that
    my $current_system = 'unknown';

    if ( $subvol && $subvol =~ /\s*Name:\s+([^\s]+)/x ) {
        my $current_volume = $1;
        $current_system = $current_volume if ( exists $possible_systems->{$current_volume} );
        say $current_system if $print;
    }
    return $current_system;
}

sub _get_chroot ($print) {

    print_table( 'Checking for chroot ', ' ', ': ' ) if $print;

    # i tried a lot of things. so far, it seems the internet is right
    # http://unix.stackexchange.com/questions/14345/how-do-i-tell-im-running-in-a-chroot
    my ( $root_device_number, $root_inode ) = stat('/');
    my ( $proc_device_number, $proc_inode ) = stat('/proc/1/root/.');
    my $chroot = 1;

    $chroot = 0 if ( $proc_device_number && $proc_inode && $root_device_number eq $proc_device_number && $root_inode eq $proc_inode );
    say $chroot if $print;

    return $chroot;
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

    # when the match did not work, the result is the same as 'Not Found'. This might be problematic.
    if ( $print && scalar keys $release_h->%* >= 1 ) {    # base has one, hostos 2 entries
        say 'OK';
    }
    die 'ERROR: File not parsed correctly' unless scalar keys $release_h->%*;
    return $release_h;
}

sub _get_target_system ($current_system) {

    for my $target_system ( sort keys $possible_systems->%* ) {
        return $target_system unless $current_system eq $target_system;
    }
    die "ERROR: no target system";
}

sub _get_first_system () {

    for my $system ( sort keys $possible_systems->%* ) {
        return $system;
    }
    die "ERROR: no target system";
}

#################################

sub get_system ( $p, $print = 0 ) {

    $print = 1 if $print eq 'print';

    my $current_system = _get_root($print);
    my $is_chroot      = _get_chroot($print);
    my $release        = _get_release( $p->{release_file}, $print );
    my $system         = {
        current => $current_system,
        chroot  => $is_chroot ? 'yes' : 'no',
        release => $release,
    };

  # Possible state matrix:
  # - possible subvolume:  chroot/release modify
  #   - A Release, in chroot: cant be chrooted in current system, so the current subvolume must be the target system.
  #                           as the current system can neither be known nor reached, set current system to unknown
  #       --> current_system: unknown   target_system: current_subvolume
  #   - A Release, no chroot: HostOS normal operation
  #       --> current_system: current_subvolume   target_system: !current_system
  #   - No release, in chroot: release file has not been created yet, meaning boostrap on buildhost.
  #       --> current_system: unknown   target_system: current_subvolume
  #   - No release, no chroot: impossible. Without a chroot on a possible system, there can not *not* be a release file.
  # - No possible subvolume:
  #   - in chroot: impossible. can't be in a chroot of an unknown subvolume
  #   - no chroot: a rescue environment of some sort. likely node installation or buildhost bootstrap. which would mean the target is the first possible system.
  #       --> current_system: unknown  target_system: system1 (initial assumption)
  # This is considered to be the source of truth of state. Don't make adjustments down the line on what the target system is. Do it here
  # if-cascade was chosen deliberately: The Comments above are the only truth, and this is the exact replica of it. Please don't be clever.

    if ( exists $possible_systems->{$current_system} ) {
        if ( scalar keys $release->%* >= 1 ) {
            if ($is_chroot) {
                $system->{current} = 'unknown';
                $system->{target}  = $current_system;
            }
            else {
                $system->{target} = _get_target_system($current_system);
            }
        }
        else {
            if ($is_chroot) {
                $system->{current} = 'unknown';
                $system->{target}  = $current_system;
            }
            else {
                die 'ERROR: Impossible state';
            }
        }
    }
    else {
        if ($is_chroot) {
            die 'ERROR: Impossible state';
        }
        else {
            $system->{current} = 'unknown';
            $system->{target}  = _get_first_system();
        }
    }
    return $system;
}

