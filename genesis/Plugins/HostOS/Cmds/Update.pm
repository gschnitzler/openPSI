package Plugins::HostOS::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Find;
use Archive::Tar;

use Plugins::HostOS::Libs::Parse::Fstab qw(read_fstab write_fstab);
use Plugins::HostOS::Libs::Parse::Grub qw(read_grub write_grub);

use PSI::RunCmds qw(run_system);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(import_update);

###################################################

sub _extract_tarball ( $tarball, $mtype, $target ) {

    my $tmp_tarball = '/tmp/boot_update.tar';

    print_table 'Unpacking Tarball', ' ', ': ';
    run_system "xz -f -k -d --stdout $tarball > $tmp_tarball";    # do not die
    say 'OK';

    print_table 'Reading Tarball', ' ', ': ';
    my $tar       = Archive::Tar->new($tmp_tarball);
    my @files     = ();
    my $filecount = 0;
    my $latest    = {};
    say 'OK';

    foreach my $file ( $tar->list_files ) {

        # ignore files that should not be in the tarball in the first place
        next if ( $file =~ m/initramfs|lost|lilo[.]conf|grub/x );
        if ( $file =~ m/\/(System.map|kernel)-(.*)/x ) {

            my $syskern = $1;
            my $rest    = $2;
            next if ( $rest !~ /^$mtype/x );    # ignore wrong mtype

            my $fullfile = $file;
            $fullfile =~ s/^[.]\///x;
            $filecount++;
            $latest->{$syskern} = $fullfile;
        }

        # only install the dracut file for the target system
        if ( $file =~ m/\/dracut-(system.)[.]img/x ) {

            my $system = $1;
            next unless ( $system eq $target );
        }

        push @files, $file;
    }

    die "ERROR: Too many/few ($filecount) kernel/System.map entries for machine type $mtype in tarball. don't know wich to choose"
      unless ( $filecount == 2 );
    die 'ERROR: No System.map/Kernel Pair found' unless ( scalar keys $latest->%* == 2 );

    foreach my $file (@files) {

        print_table 'writing to /boot/', ' ', ": $file\n";
        $tar->extract_file( $file, join( '', '/boot/', $file ) );
    }

    unlink $tmp_tarball or print "$? $!";
    return ( $latest->{kernel} );
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

##################################################################################
#### frontend
sub update_boot ( $query, @ ) {

    my $bootstrap      = $query->('state bootstrap');
    my $chroot         = $query->('state chroot');
    my $image          = $query->('state image');
    my $mtype          = $query->('state machine_type');
    my $current_system = $query->('state current');
    my $target_system  = $query->('state target');
    my $grub_f         = $query->('grub');
    my $grub_template  = $query->('grub_template');

    print_table 'Updating /boot', ' ', ": $image \n";

    my $switched = _get_switched( $grub_f, $current_system );

    die 'can\'t use update boot in bootstrap mode, while in chroot, or while switched'
      if ( $bootstrap eq 'yes' || $chroot eq 'yes' || $switched eq 'yes' );

    my $grub      = read_grub($grub_f);
    my $cursys    = $grub->{current};
    my $curkernel = $grub->{$cursys}->{kernel};
    my $tarsys    = join( '-', $target_system, $mtype );

    die 'ERROR: grub.cfg seems to be in the wrong state. reinstall it.' unless ( exists( $grub->{$tarsys} ) );

    _delete_old_kernel($curkernel);

    $grub->{$tarsys}->{kernel} = _extract_tarball( $image, $mtype, $target_system );

    # write new genesis to disk
    write_grub(
        {
            template => $grub_template,
            grub     => $grub,
            path     => $grub_f,
        }
    );

    return;
}

sub update_fstab ( $query, @ ) {

    my $fstab_f        = $query->('fstab');
    my $disk1          = $query->('disk1');
    my $disk2          = $query->('disk2');
    my $raid_level     = $query->('raid_level');
    my $grub_f         = $query->('grub');
    my $target_system  = $query->('target');
    my $current_system = $query->('current');
    my $bootstrap      = $query->('bootstrap');
    my $chroot         = $query->('chroot');

    print_table 'Updating fstab', ' ', ": \n";

    # system cannot be switched when in chroot.
    if ( $chroot ne 'yes' ) {
        die 'ERROR: system is switched' if ( _get_switched( $grub_f, $current_system ) eq 'yes' );
    }

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
                    fstab            => 'paths hostos FSTAB',
                    grub             => 'paths hostos GRUB',
                    disk1            => 'machine self RAID DISK1',
                    disk2            => 'machine self RAID DISK2',
                    raid_level       => 'machine self RAID LEVEL',
                    target           => 'state root_target',
                    current          => 'state root_current',
                    chroot           => 'state chroot',
                    bootstrap        => 'state bootstrap',
                    possible_systems => 'state possible_systems',
                }
            },
            boot => {
                CMD  => \&update_boot,
                DESC => 'Update HostOS kernel',
                HELP => ['Extracts latest kernel image to boot volume'],
                DATA => {
                    state => {
                        chroot           => 'state chroot',
                        possible_systems => 'state possible_systems',
                        bootstrap        => 'state bootstrap',
                        machine_type     => 'state machine_type',
                        current          => 'state root_current',
                        target           => 'state root_target',
                        image            => 'state images image boot latest'
                    },
                    grub          => 'paths hostos GRUB',
                    grub_template => 'service grub TEMPLATES',
                }
            }
        }
    };
}
1;
