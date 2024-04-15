package Plugins::HostOS::Cmds::Chroot;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::RunCmds qw(run_system);
use PSI::Parse::File qw(write_file);

our @EXPORT_OK = qw(import_chroot);

#################################################################
# this module is old and deeply entangled with everything.
# if you are in the process of redesigning, get rid of this
#################################################################

sub _add_root_partition($disk) {
    $disk =~ /nvme/
      ? return join( '', $disk, 'p3' )
      : return join( '', $disk, '3' );
}

sub _add_boot_partition($disk) {
    $disk =~ /nvme/
      ? return join( '', $disk, 'p2' )
      : return join( '', $disk, '2' );
}

sub _write_file ( $path, @data ) {

    write_file(
        {
            PATH    => $path,
            CONTENT => [ join( "\n", @data ) ],
        }
    );
    return;
}

sub _nop(@) {
    return;
}

sub _chroot_macro ( $action, $query, @ ) {

    # properly integrate the bashinit script into the templates and generate it with 'config'
    # also see to it that the file paths are substituted properly

    my $bashinit  = $query->('bashinit');
    my $mount     = $query->('mount');
    my $genesis   = $query->('genesis');
    my $psi       = $query->('psi');
    my $data_root = $query->('data_root');
    my @data      = ();
    my $bashinit2 .= '_2';

    _create_bashinit( $mount, $bashinit, $bashinit2 );

    if ($action) {

        @data = (
            'env-update',
            'source /etc/profile',
            'export PS1="(chroot) $PS1"',
            "rm $bashinit2",
            "cd $genesis && ./require.sh",
            'genesis macro load',
            "umount -lf $psi",
            'exit',
        );
    }
    else {

        @data = (
            'env-update',
            'source /etc/profile',
            'export PS1="(chroot) $PS1"',
            "rm $bashinit2",
            'genesis macro load',
            'exit',
        );
    }

    _write_file( "$mount/$bashinit2", @data );

    say 'spawning new shell...';
    run_system "exec chroot $mount /bin/bash --init-file $bashinit";

    return;
}

sub _enter_shell ( $action, $query, @ ) {

    my $bashinit  = $query->('bashinit');
    my $bashinit2 = join( '', $bashinit, '_2' );
    my $mount     = $query->('mount');
    my $genesis   = $query->('genesis');
    my $disk      = _add_root_partition $query->('disk');
    my $target    = $query->('target');
    my $data_root = $query->('data_root');

    _mount_target($query);
    _create_bashinit( $mount, $bashinit, $bashinit2 );

    my @data = (
        #
        'env-update',
        'source /etc/profile',
        'export PS1="(chroot) $PS1"',
        "rm $bashinit2",
        'DONT_MOUNT_BOOT=1 && export DONT_MOUNT_BOOT',
    );
    push @data, "cd $genesis && ./require.sh && genesis" if ( $action == 2 );
    _write_file( "$mount/$bashinit2", @data );
    _mount_dev($query);

    if ($action) {
        _mount_databoot($query);
        _mount_genesis($query) if ( $action == 2 );
    }
    else {
        _mount_rbind($query);
    }

    say 'spawning new shell...';
    run_system "exec chroot $mount /bin/bash --init-file $bashinit";

    _umount_dev($query);
    _umount_databoot($query);
    _umount_genesis($query) if ( $action == 2 );
    _umount_target($query);

    say 'Finished.';
    return;
}

sub _create_bashinit ( $mount, $bashinit, $bashinit2 ) {
    say 'creating chroot entry file...';
    _write_file(
        #
        "$mount/$bashinit",
        "rm $bashinit",
        "/bin/bash  --init-file $bashinit2 -i",
        'exit'
    );
    return;
}

sub _mount_dev ( $query, @ ) {

    my $mount = $query->('mount');
    say "mounting /proc /sys /dev to $mount ...";
    run_system "mount -t proc proc $mount/proc";    # using mount with system always throws an exception. so don't check
    run_system "mount --rbind /sys $mount/sys";
    run_system "mount --rbind /dev $mount/dev";
    run_system "mount --bind /run $mount/run";
    return;
}

sub _umount_dev ( $query, @ ) {

    my $mount = $query->('mount');
    say 'unmounting /proc /sys /dev';
    run_system \&_nop, "umount -lf $mount/proc";
    run_system \&_nop, "umount -lf $mount/sys";
    run_system \&_nop, "umount -lf $mount/dev";
    run_system \&_nop, "umount -lf $mount/run";
    return;
}

sub _mount_target ( $query, @ ) {

    my $mount  = $query->('mount');
    my $disk   = _add_root_partition $query->('disk');
    my $target = $query->('target');
    say "mounting $target to $mount ...";
    run_system "mkdir -p $mount";    # using mount with system always throws an exception. so don't check
    run_system "mount -o subvol=$target $disk $mount";
    return;
}

sub _mount_genesis ( $query, @ ) {

    my $mount     = $query->('mount');
    my $data_root = $query->('data_root');
    my $genesis   = $query->('genesis');
    my $psi       = $query->('psi');
    say "mounting $mount$data_root/genesis.img to $mount$psi ...";
    run_system "mount $mount$data_root/genesis.img  $mount$psi";    # using mount with system always throws an exception. so don't check
    return;
}

sub _mount_databoot ( $query, @ ) {

    my $mount       = $query->('mount');
    my $disk        = _add_root_partition $query->('disk');
    my $boot_disk   = _add_boot_partition $query->('disk');
    my $data_root   = $query->('data_root');
    my $target_data = "$mount$data_root";
    my $target_boot = "$mount/boot";

    say "mounting /boot and /data to $mount ...";
    run_system "mkdir -p $target_boot";    # using mount with system always throws an exception. so don't check
    run_system "mount $boot_disk $target_boot";
    run_system "mkdir -p $target_data";
    run_system "mount -o subvol=\"data\" $disk $target_data";
    return;
}

sub _mount_boot ( $query, @ ) {

    my $mount       = $query->('mount');
    my $disk        = _add_root_partition $query->('disk');
    my $boot_disk   = _add_boot_partition $query->('disk');
    my $target_boot = "$mount/boot";
    say 'mounting /boot ...';
    run_system "mkdir -p $target_boot";    # using mount with system always throws an exception. so don't check
    run_system "mount $boot_disk $target_boot";
    return;
}

sub _umount_target ( $query, @ ) {

    my $mount = $query->('mount');
    say "unmounting $mount";
    run_system \&_nop, "umount -lf $mount";
    return;
}

sub _umount_boot ( $query, @ ) {

    my $mount = $query->('mount');
    say "unmounting $mount/boot";
    run_system \&_nop, "umount -lf $mount/boot";
    return;
}

sub _umount_genesis ( $query, @ ) {

    my $mount   = $query->('mount');
    my $genesis = $query->('genesis');
    my $psi     = $query->('psi');
    say "unmounting $mount$psi";
    run_system \&_nop, "umount -lf $mount$psi";
    return;
}

sub _mount_rbind ( $query, @ ) {

    my $mount       = $query->('mount');
    my $data_root   = $query->('data_root');
    my $target_data = "$mount$data_root";
    my $target_boot = "$mount/boot";
    say "mounting /boot and $data_root to $mount ...";
    run_system "mkdir -p $target_boot";    # using mount with system always throws an exception. so don't check
    run_system "mkdir -p $target_data";
    run_system "mount --rbind $data_root $target_data";
    run_system "mount --rbind \"/boot\" $target_boot";
    return;
}

sub _mount_rbind_data ( $query, @ ) {

    my $mount       = $query->('mount');
    my $data_root   = $query->('data_root');
    my $target_data = "$mount$data_root";
    say "mounting $data_root to $target_data ...";
    run_system "mkdir -p $target_data";    # using mount with system always throws an exception. so don't check
    run_system "mount --rbind $data_root $target_data";
    return;
}

sub _umount_rbind_data ( $query, @ ) {

    my $mount       = $query->('mount');
    my $data_root   = $query->('data_root');
    my $target_data = "$mount$data_root";
    say "unmounting $data_root in $mount ...";
    run_system \&_nop, "umount -lf $target_data";
    return;
}

sub _umount_databoot ( $query, @ ) {

    my $mount       = $query->('mount');
    my $data_root   = $query->('data_root');
    my $target_data = "$mount$data_root";
    my $target_boot = "$mount/boot";
    say "unmounting /boot and $data_root in $mount ...";
    run_system \&_nop, "umount -lf $target_data";
    run_system \&_nop, "umount -lf $target_boot";
    return;
}

###################

sub import_chroot () {

    my %all = (
        genesis   => 'paths psi GENESIS',
        psi       => 'paths psi ROOT',
        mount     => 'paths hostos MOUNT',
        disk      => 'machine self RAID DISK1',
        data_root => 'paths data ROOT',
    );

    my $struct = {
        enter => {
            bootstrap => {
                CMD  => sub (@arg) { _enter_shell( '1', @arg ); },
                DESC => 'enter target system chroot (in bootstrap)',
                HELP => ['spawns a shell in target system chroot (in bootstrap)'],
                DATA => {
                    %all,
                    bashinit => 'paths hostos BASHINIT',
                    target   => 'state root_target',
                }
            },
            initial => {
                CMD  => sub (@arg) { _enter_shell( '2', @arg ); },
                DESC => 'enter target system chroot (in bootstrap) and setup genesis',
                HELP => ['spawns a shell in target system chroot (in bootstrap) and setup genesis'],
                DATA => {
                    %all,
                    bashinit => 'paths hostos BASHINIT',
                    target   => 'state root_target',
                }
            },
            chroot => {
                shell => {
                    CMD  => sub (@arg) { _enter_shell( '0', @arg ); },
                    DESC => 'enter target system chroot (non bootstrap)',
                    HELP => ['spawns a shell in target system chroot (non bootstrap)'],
                    DATA => {
                        %all,
                        bashinit => 'paths hostos BASHINIT',
                        target   => 'state root_target',
                    }
                },
                macro => {
                    CMD  => sub (@arg) { _chroot_macro( 0, @arg ) },
                    DESC => 'performs a chroot',
                    HELP => [ 'usage:', 'chroot now: chroots to mountpath' ],
                    DATA => { %all, bashinit => 'paths hostos BASHINIT', }
                },
                initial => {
                    CMD  => sub (@arg) { _chroot_macro( 1, @arg ) },
                    DESC => 'performs a chroot for initial bootstrapping',
                    HELP => [ 'usage:', 'chroot initial: chroots to mountpath and setups genesis environment' ],
                    DATA => {
                        %all,
                        bashinit => 'paths hostos BASHINIT',

                    }
                },
            }
        },
        mount => {
            target => {
                CMD  => \&_mount_target,
                DESC => 'mount target system',
                HELP => ['mount target system'],
                DATA => {
                    %all,
                    target => 'state root_target',
                }
            },
            dev => {
                CMD  => \&_mount_dev,
                DESC => 'mount target dev',
                HELP => ['mount target dev'],
                DATA => {%all}

            },
            databoot => {
                CMD  => \&_mount_databoot,
                DESC => 'mount target data and boot',
                HELP => ['mount target data and boot'],
                DATA => {%all}
            },
            boot => {
                CMD  => \&_mount_boot,
                DESC => 'mount boot',
                HELP => ['mount boot'],
                DATA => {%all}
            },
            rbind => {
                CMD  => \&_mount_rbind,
                DESC => 'mount target rbind',
                HELP => ['uount target rbind'],
                DATA => {%all}
            },
            targetdev => {
                CMD  => sub (@arg) { _mount_target(@arg); _mount_dev(@arg); },
                DESC => 'mount target system and dev',
                HELP => ['mount target system and dev'],
                DATA => { %all, target => 'state root_target', }
            },
            bootstrap => {
                CMD  => sub (@arg) { _mount_target(@arg); _mount_dev(@arg); _mount_boot(@arg); _mount_rbind_data(@arg) },
                DESC => 'mount target system and dev',
                HELP => ['mount target system and dev'],
                DATA => { %all, target => 'state root_target', }
            },
            system => {
                CMD => sub (@arg) {
                    _mount_target(@arg);
                    _mount_rbind(@arg);
                    _mount_dev(@arg);
                },
                DESC => 'mount target system and dev',
                HELP => ['mount target system and dev'],
                DATA => { %all, target => 'state root_target', }
            },
        },
        unmount => {
            target => {
                CMD  => \&_umount_target,
                DESC => 'unmount target system',
                HELP => ['unmount target system'],
                DATA => {%all}
            },
            dev => {
                CMD  => \&_umount_dev,
                DESC => 'unmount target dev',
                HELP => ['unmount target dev'],
                DATA => {%all}
            },
            databoot => {
                CMD  => \&_umount_databoot,
                DESC => 'unmount target data and boot',
                HELP => ['unmount target data and boot'],
                DATA => {%all}
            },
            bootstrap => {
                CMD  => sub (@arg) { _umount_rbind_data(@arg); _umount_boot(@arg); _umount_dev(@arg); _umount_target(@arg) },
                DESC => 'unmount bootstrap',
                HELP => ['unmount bootstrap'],
                DATA => {%all}
            },
            boot => {
                CMD  => \&_umount_boot,
                DESC => 'unmount boot',
                HELP => ['unmount boot'],
                DATA => {%all}
            },
            system => {
                CMD => sub (@arg) {
                    _umount_dev(@arg);
                    _umount_databoot(@arg);
                    _umount_target(@arg);
                },
                DESC => 'unmount target system completely',
                HELP => ['unmount target system completly'],
                DATA => {%all}
            }
        }
    };
    return $struct;
}

1;
