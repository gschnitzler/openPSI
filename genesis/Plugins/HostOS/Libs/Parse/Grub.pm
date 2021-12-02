package Plugins::HostOS::Libs::Parse::Grub;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Find;
use Readonly;

use PSI::Parse::File qw(parse_file write_file);
use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(read_grub write_grub gen_grub);

Readonly my $GRUB_LINUX         => qr{\s+linux\s+};
Readonly my $GRUB_KERNEL_PATH   => qr{/boot/};
Readonly my $GRUB_KERNEL        => qr{[^\s]+};
Readonly my $GRUB_ROOT_PREFIX   => qr{root=};
Readonly my $GRUB_ROOT          => qr{[^\s]+};
Readonly my $GRUB_SUBVOL_PREFIX => qr{subvol=};
Readonly my $GRUB_SUBVOL        => qr{[^\s,]+};
Readonly my $GRUB_LINE          => qr{
    $GRUB_LINUX
    $GRUB_KERNEL_PATH
    ($GRUB_KERNEL)
    \s+.*
    $GRUB_ROOT_PREFIX
    ($GRUB_ROOT)
    .*
    $GRUB_SUBVOL_PREFIX
    ($GRUB_SUBVOL)
    }x;

###################################################################

sub _get_current_kernel ($mtype) {

    my $regex   = qr /^kernel-$mtype-.*/x;
    my @kernels = ();
    my $wanted  = sub ( $file, $kernels, $regex_local ) {
        push $kernels->@*, $file if $file =~ m/$regex_local/x;
    };
    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink
    find( sub { &$wanted( $_, \@kernels, $regex ) }, '/boot/' );

    @kernels = sort @kernels;
    my $newest = pop @kernels;

    die 'ERROR: could not find a suitable kernel. maybe the machine type does not match' unless ($newest);
    return $newest;
}

sub _struct_grub_flushheap ( $struct, $heap ) {

    my $name = delete $heap->{system};
    if ($name) {
        $struct->{$name} = { $heap->%* };
        $heap = {};
    }
    die 'ERROR: Parser error' unless ( exists( $struct->{current} ) );
    return;
}

# this is not a complete parser like the lilo version was.
# instead we just extract what we need
sub _struct_grub ( $struct, $heap, $flush_heap, $line ) {

    # default system
    if ( $line =~ m/^set\s+default=["']([^'"]+)["']/x ) {
        $struct->{current} = $1;
        return;
    }

    # new menu entry
    if ( $line =~ m/^menuentry\s+["']([^'"]+)["']/x ) {
        $heap->{system} = $1;
        return;
    }

    # add to image key value
    if ( $line =~ $GRUB_LINE && $heap->%* ) {
        $heap->{kernel} = $1;
        $heap->{root}   = $2;
        $heap->{subvol} = $3;
        return;
    }

    if ( $line =~ m/^\s*}/x && $heap->%* ) {
        &$flush_heap( $struct, $heap );
    }
    return;
}

sub _grub_write_disk ( $conf, $path ) {

    print_table 'Writing ', $path, ': ';
    write_file(
        {
            PATH    => $path,
            CONTENT => $conf,
        }
    );

    say 'OK';
    return;
}

# generate grub.cfg for config module.
# it will only handle a single kernel for both systems,
# and will always use the newest one fit for the mtype.
# only use is for 1st time generation in bootstrap while in chroot.
# for other cases use the update frontend
sub gen_grub ($query) {

    my $mtype       = $query->('config grub machine_type');
    my $grub_path   = $query->('config grub grubfile');
    my $root        = $query->('config grub root');
    my $template    = $query->('templates grub');
    my $header_f    = 'grub.cfg_header';
    my $menuentry_f = 'grub.cfg_kernel';
    print_table 'Generating grub.cfg', ' ', ': ';

    {
        local ( $?, $! );
        if ( file_exists $grub_path && !-z $grub_path ) {
            say 'skipped (file exists)';
            return;
        }
    }

    my $newestkernel = _get_current_kernel($mtype);
    my @grubcfg      = ();
    my $subst        = {
        plugin => {
            grub => {
                current => "system1-$mtype",
                system  => "system1-$mtype",
                kernel  => $newestkernel,
                root    => $root,
                subvol  => 'system1'
            }
        }
    };

    push( @grubcfg, check_and_fill_template( $template->{$header_f}->{CONTENT},    $subst ) );
    push( @grubcfg, check_and_fill_template( $template->{$menuentry_f}->{CONTENT}, $subst ) );

    $subst->{plugin}->{grub}->{system} = "system2-$mtype";
    $subst->{plugin}->{grub}->{subvol} = 'system2';

    push( @grubcfg, check_and_fill_template( $template->{$menuentry_f}->{CONTENT}, $subst ) );

    my $cf = {};
    $cf->{LOCATION} = $template->{$header_f}->{LOCATION};
    $cf->{CHMOD}    = $template->{$header_f}->{CHMOD};

    foreach (@grubcfg) {
        push $cf->{CONTENT}->@*, $_->@*;
    }

    say 'OK';
    return ($cf);
}

# reads systems grub
sub read_grub ( $grub_f, $print = 1 ) {

    print_table( 'Reading grub config ', $grub_f, ': ' ) if ($print);

    my $grub_struct = parse_file( $grub_f, \&_struct_grub, \&_struct_grub_flushheap );
    die 'ERROR: Parser Error' if ( !$grub_struct->{current} );
    say 'OK' if ($print);
    return ($grub_struct);
}

# write systems grub
sub write_grub( $p ) {

    my $template    = $p->{template};
    my $grub        = $p->{grub};
    my $grub_f      = $p->{path};
    my $header_f    = 'grub.cfg_header';
    my $menuentry_f = 'grub.cfg_kernel';

    print_table 'Generating grub config', ' ', ': ';

    my @grubcfg = ();
    my $subst->{plugin}->{grub}->{current} = delete $grub->{current};

    push( @grubcfg, check_and_fill_template( $template->{$header_f}->{CONTENT}, $subst ) );

    foreach my $system ( keys $grub->%* ) {

        my $subvol = $system;
        $subvol =~ s/-.*//x;
        $subst->{plugin}->{grub}->{system} = $system;
        $subst->{plugin}->{grub}->{kernel} = $grub->{$system}->{kernel};
        $subst->{plugin}->{grub}->{root}   = $grub->{$system}->{root};
        $subst->{plugin}->{grub}->{subvol} = $subvol;

        push( @grubcfg, check_and_fill_template( $template->{$menuentry_f}->{CONTENT}, $subst ) );
    }

    my @conf = ();
    foreach my $array (@grubcfg) {
        foreach my $line ( $array->@* ) {
            push @conf, join( '', $line, "\n" );
        }
    }

    say 'OK';
    _grub_write_disk( \@conf, $grub_f );
    return;
}

