package Plugins::HostOS::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Find;
use Archive::Tar;

use Plugins::HostOS::Libs::Parse::Fstab qw(read_fstab write_fstab);
use Plugins::HostOS::Libs::Parse::Grub  qw(read_grub write_grub);

use PSI::Parse::Dir qw(get_directory_list);
use PSI::RunCmds    qw(run_system run_cmd);
use PSI::Console    qw(print_table);

our @EXPORT_OK = qw(import_update);

###################################################

sub _extract_tarball ( $tarball, $targets ) {

    my $tmp_tarball = '/tmp/boot_update.tar';

    print_table 'Unpacking Tarball', ' ', ': ';
    run_system "zstd -qfdk --stdout $tarball > $tmp_tarball";    # do not die
    say 'OK';

    print_table 'Reading Tarball', ' ', ': ';
    my $tar   = Archive::Tar->new($tmp_tarball);
    my @files = ();

    #my $filecount = 0;
    #my $latest    = {};
    say 'OK';

    foreach my $file ( $tar->list_files ) {

        for my $target ( keys $targets->%* ) {
            my $path = $targets->{$target};
            next unless $file =~ /$path$/;
            push @files, $file;
        }

        #next if ( $file =~ m/initramfs|lost|lilo[.]conf|grub|EFI/x );
        #if ( $file =~ m/[\/]*(System.map|kernel)-(.*)/x ) {
        #    my $syskern = $1;
        #    my $rest    = $2;
        #next if ( $rest !~ /^$mtype/x );    # ignore wrong mtype
        #my $fullfile = $file;
        #$fullfile =~ s/^[.]\///x;
        #$filecount++;
        #$latest->{$syskern} = $fullfile;
        #}

        # only install the dracut file for the target system
        #if ( $file =~ m/[\/]*dracut-(system.).*[.]img/x ) {
        #    my $system = $1;
        #    next unless ( $system eq $target );
        #}
        #push @files, $file;
    }
    die 'ERROR: Not all required entries for machine type in tarball.' unless ( scalar @files == scalar keys $targets->%* );

    #die "ERROR: Too many/few ($filecount) kernel/System.map entries for machine type in tarball. don't know wich to choose" unless ( $filecount == 2 );
    #die 'ERROR: No System.map/Kernel Pair found' unless ( scalar keys $latest->%* == 2 );

    foreach my $file (@files) {

        print_table 'writing to /boot/', ' ', ": $file\n";
        my $fp = join( '', '/boot/', $file );
        unlink $fp or print "$? $!";
        $tar->extract_file( $file, $fp );
    }

    unlink $tmp_tarball or print "$? $!";
    return;
}

sub _delete_old_kernel ($curkernel) {

    print_table 'Deleting unused Kernels', ' ', ": \n";

    my $regex   = qr /(kernel|System[.]map)-.*/x;
    my @kernels = ();
    my $curmap  = $curkernel;
    $curmap =~ s/^kernel/System\.map/x;

    my $wanted = sub ( $file, $kernels, $regexp, $ignore ) {

        return unless ( $file =~ m/$regexp/x );

        if ( exists( $ignore->{$file} ) ) {
            print_table 'preserved (current sys)', ' ', ": $file\n";
            return;
        }

        print_table 'marked for deletion', ' ', ": $file\n";
        push $kernels->@*, $file;
        return;
    };

    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink
    find(
        sub (@) {
            &$wanted( $_, \@kernels, $regex, { $curmap => 0, $curkernel => 0 } );
        },
        '/boot/'
    );
    die "ERROR: $!" if $!;

    if ( scalar @kernels >= 1 ) {

        foreach my $kernel (@kernels) {
            my $fullpath = join( '', '/boot/', $kernel );
            unlink $fullpath or die 'unlink failed';
        }
        return;
    }

    say 'no files marked for deletion...';
    return;
}

# there is a reason this is not included in hostos state:
# during bootstrap, there is either none or the rescue systems grub config in place
# calling read_grub() will result in an error.
sub _get_switched ( $grub_path, $current_sys ) {

    my $switched           = 'no';
    my $grub               = read_grub($grub_path);
    my $grub_curent_kernel = $grub->{current};
    my $grub_current_root  = $grub->{$grub_curent_kernel}->{subvol};
    $switched = 'yes' if ( $current_sys ne $grub_current_root );

    return $switched;
}

sub _get_latest ($h) {
    for my $key ( sort { $b <=> $a } keys $h->%* ) {
        return $key;
    }
    return;
}

sub _get_root_partition ($disk) {

    $disk = join '', $disk, 'p' if ( $disk =~ /nvme/ );
    $disk = join '', $disk, '3';
    return $disk;
}

sub _get_btrfs_device_string ( $disk1, $disk2, $raid_level ) {

    my $string = "device=$disk1";

    if ( $raid_level ne 'raidS' ) {
        $string = join( '', $string, ",device=$disk2" );
    }
    $string = join( '', $string, ',subvol=' );
    return $string;
}

sub _get_wanted_system ( $possible_systems, $current_system, $chroot ) {
    my $wanted = {};
    #for my $pos_sys ( keys $possible_systems->%* ) {
    #    my $path = "$pos_sys\.efi";
    #    $wanted->{$pos_sys} = $path;# if ( $current_system ne $pos_sys ); # because the target system is overridden in state, this does not work anymore... default to build all systems until a proper fix is implemented
    #}

    #return $wanted if ( scalar keys $wanted->%* );

    # add all if the above did not work. This is triggered on buildhost
    for my $pos_sys ( keys $possible_systems->%* ) {
        $wanted->{$pos_sys} = "$pos_sys\.efi";
    }

    return $wanted;
}

sub _get_kernels ($kernel_source_path) {

    my $kernels = {};
    for my $file ( keys get_directory_list($kernel_source_path)->%* ) {
        if ( $file =~ /([^-]+)-([^-]+)-([^-]+)-([^-]+)-(.*)/ ) {
            my ( $file_type, $mtype, $tag, $version, $rest ) = ( $1, $2, $3, $4, $5 );    # drop the mtype
            $kernels->{$tag}->{$file_type} = { version => $version, path => join( '/', $kernel_source_path, $file ), rest => $rest };
        }
    }
    return $kernels;
}

##################################################################################
#### frontend
sub update_boot ( $query, @ ) {

    print_table 'Updating /boot', ' ', ":\n";
    my $chroot           = $query->('state chroot');
    my $current_system   = $query->('state current');
    my $possible_systems = $query->('state possible_systems')->{system};
    my $disk1            = $query->('disk1');
    my $disk2            = $query->('disk2');
    my $raid_level       = $query->('raid_level');
    my $disk1_root       = _get_root_partition($disk1);
    my $disk2_root       = _get_root_partition($disk2);
    my $btrfs_dev        = _get_btrfs_device_string( $disk1_root, $disk2_root, $raid_level );
    my $wanted           = _get_wanted_system( $possible_systems, $current_system, $chroot );
    my $kernels          = _get_kernels('/usr/kernel');
    my $kernel_latest    = $kernels->{ _get_latest($kernels) }->{kernel};
    my $efi_path         = '/boot';
    my $modules_path     = '/lib/modules';

    die "ERROR: no kernel found" unless $kernel_latest->{path};

    for my $system ( keys $wanted->%* ) {
        my $target_path         = join( '/', $efi_path,     $wanted->{$system} );
        my $hostos_modules_path = join( '',  $modules_path, '/', $kernel_latest->{version}, '-', $kernel_latest->{rest} );
        my @cmd                 = (

            #'DRACUT_KMODDIR_OVERRIDE=1',
            'dracut --hostonly --force --uefi --zstd --early-microcode -m "btrfs base rootfs-block kernel-modules fs-lib img-lib usrmount udev-rules i18n"',

            #"--kmoddir $hostos_modules_path",
            "--mount \"$disk1_root / btrfs subvol=$system\"",
            "--kernel-image $kernel_latest->{path}",
            "--kernel-cmdline \"net.ifnames=0 ipv6.disable=1 ro root=$disk1_root rootflags=degraded,$btrfs_dev$system\"",
            $target_path
        );

        print_table "writing $system", $kernel_latest->{path}, ": $target_path\n";

        #run_cmd("mkdir -p $efi_path"); # not needed now that its just /boot
        {
            local $!;
            unlink $target_path or print "$? $!" if ( -e $target_path );
        }
        {
            # the running kernel is most likely not the same version as the modules in chroot (and the kernel to boot).
            # there is the dracut --kmoddir $modules_path switch, that requires the DRACUT_KMODDIR_OVERRIDE=1 env variable to work
            # however, without diving into the code, I am not entirely sure there are no side effects (it being redhat code and having observed boot issues)
            # this is a tried and tested approach:
            # run_cmd('ln -s /lib/modules/$(ls /lib/modules/ | head -n1) /lib/modules/$(uname -r) > /dev/null 2>&1 || true');
            # as the correct modules dir is known, lets simplify to:
            local $!;
            run_cmd( join( '', "ln -s $hostos_modules_path $modules_path/", '$(uname -r) > /dev/null 2>&1 || true' ) );
        }

        run_cmd( join( ' ', @cmd ) );
    }

    return;
}

sub update_fstab ( $query, @ ) {

    my $fstab_f        = $query->('fstab');
    my $disk1          = $query->('disk1');
    my $disk2          = $query->('disk2');
    my $raid_level     = $query->('raid_level');
    my $target_system  = $query->('target');
    my $current_system = $query->('current');
    my $bootstrap      = $query->('bootstrap');
    my $chroot         = $query->('chroot');

    print_table 'Updating fstab', ' ', ": \n";

    my $fstab = read_fstab($fstab_f);
    $fstab->{'/'}->{subvol} = $current_system;

    write_fstab(
        {
            fstab      => $fstab,
            path       => $fstab_f,
            disk1      => $disk1,
            disk2      => $disk2,
            raid_level => $raid_level
        }
    );

    return;
}

###############################################
# Frontend Functions

sub import_update () {

    return {
        update => {
            fstab => {
                CMD  => \&update_fstab,
                DESC => 'rewrites fstab',
                HELP => ['used for node installation, when the system still has the original fstab'],
                DATA => {
                    fstab => 'paths hostos FSTAB',

                    #grub             => 'paths hostos GRUB',
                    disk1      => 'machine self RAID DISK1',
                    disk2      => 'machine self RAID DISK2',
                    raid_level => 'machine self RAID LEVEL',
                    target     => 'state root_target',
                    current    => 'state root_current',
                    chroot     => 'state chroot',
                    bootstrap  => 'state bootstrap',
                }
            },
            boot => {
                CMD  => \&update_boot,
                DESC => 'Update HostOS kernel',
                HELP => ['Extracts latest kernel image to boot volume'],
                DATA => {

                    disk1      => 'machine self RAID DISK1',
                    disk2      => 'machine self RAID DISK2',
                    raid_level => 'machine self RAID LEVEL',
                    state      => {
                        possible_systems => 'state possible_systems',

                        #bootstrap        => 'state bootstrap',
                        current => 'state root_current',
                        chroot  => 'state chroot',

                        #image            => 'state images image boot latest'

                        #target           => 'state root_target',

                        #machine_type     => 'state machine_type',
                    },

                    #grub          => 'paths hostos GRUB',
                    #grub_template => 'service grub TEMPLATES',
                }
            }
        }
    };
}
1;
