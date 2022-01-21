package Plugins::Build::Cmds::Build;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use InVivo qw(kexists kdelete);
use IO::Config::Check qw(file_exists);
use Tree::Slice qw(slice_tree);
use Tree::Build qw(build_image_tree);
use PSI::Parse::Dir qw(get_directory_list);
use PSI::Parse::File qw(write_file);
use PSI::Console qw(print_table count_down);
use PSI::RunCmds qw(run_cmd run_system run_open);
use PSI::Tag qw(get_tag);
use PSI::Store qw(store_image load_image);
use PSI::System::BTRFS qw(delete_btrfs_subvolume create_btrfs_snapshot create_btrfs_subvolume get_btrfs_subvolumes);

our @EXPORT_OK = qw(import_build);

Readonly my $SLEEP_CYCLE => 20;

###################################

sub _update_tree ( $tree, $dir ) {

    my $subvolumes = get_btrfs_subvolumes($dir);

    foreach my $key ( keys $tree->%* ) {

        my $image      = $tree->{$key};
        my $parent     = $image->{from}->{name};
        my $parent_tag = $image->{from}->{tag};

        print_table( 'Update Tree for:', "$parent:$parent_tag ", ': ' );

        if ( !kexists( $image, 'add', $parent ) ) {

            $parent_tag = '';
            foreach my $current_tag ( sort ( keys( $subvolumes->%* ) ) ) {
                $parent_tag = $current_tag if ( kexists( $subvolumes, $current_tag, $parent ) );
            }
        }

        die "ERROR: seems like you have to build '$parent' first" unless ($parent_tag);

        $image->{from}->{tag} = $parent_tag;
        say $parent_tag;

        return $image->{name};
    }
    return;
}

sub _clean_builddir ( $image_tree, $builddir ) {

    my @delete = ();
    my $cond   = sub ($l) {
        return 1 if ( ref $l->[0] eq 'HASH' && exists( $l->[0]->{name} ) && exists( $l->[0]->{tag} ) && exists( $l->[0]->{from} ) );
        return 0;
    };

    push @delete, join( ':', $_->[0]->{name}, $_->[0]->{tag} ) for slice_tree( $image_tree, $cond );

    foreach my $del (@delete) {
        my $p = join( '/', $builddir, split( /:/, $del ) );
        _umount_dev($p);
    }
    delete_btrfs_subvolume( $builddir, @delete );
    return;
}

sub _mount_dev ($mount) {

    print_table( 'Mounting /proc /sys /dev genesis', "$mount ", ': ' );
    run_system "mount --types proc /proc $mount/proc";
    run_system "mount --rbind /sys $mount/sys";
    run_system "mount --make-rslave $mount/sys";
    run_system "mount --rbind /dev $mount/dev";
    run_system "mount --make-rslave $mount/dev";
    run_system "mkdir -p $mount/data/psi && mount $mount/genesis.img $mount/data/psi";
    say 'OK';
    return;
}

sub _umount_dev ($mount) {

    print_table( 'Unmounting /proc /sys /dev genesis', "$mount ", ': ' );
    my $nop = sub(@) { };    # using mount with system always throws an exception. so don't check
    run_system $nop, "umount -lf $mount/proc > /dev/null 2>&1";
    run_system $nop, "umount -lf $mount/sys > /dev/null 2>&1";
    run_system $nop, "umount -lf $mount/dev > /dev/null 2>&1";
    run_system $nop, "umount -lf $mount/data/psi > /dev/null 2>&1";
    run_system "rm -f $mount/genesis.img > /dev/null 2>&1";
    say 'OK';
    return;
}

sub _format_time ($start_time) {

    my $elapsed = '';
    foreach my $e ( ( gmtime( time() - $start_time ) )[ 2, 1, 0 ] ) {
        if ( length($e) eq '1' ) {
            if ($elapsed) {
                $elapsed = "$elapsed:0$e";
            }
            else {
                $elapsed = "0$e";
            }
        }
        else {
            if ($elapsed) {
                $elapsed = "$elapsed:$e";
            }
            else {
                $elapsed = "$e";
            }
        }
    }
    return $elapsed;
}

sub _get_tmux_sessions () {

    my @tmux = run_open 'tmux ls 2>&1', sub(@) { };    # when there is no tmux running in the background, 'tmux ls' returns an error. we don't care.
    my $h    = {};

    foreach my $line (@tmux) {

        my ($name) = split( /:/, $line );
        $h->{$name} = 1;
    }
    return $h;
}

sub _assemble_images ( $config, $tag ) {

    my $images = {};
    foreach my $image ( keys $config->%* ) {

        print_table( 'Assembling', "$image ", ': ' );

        my $bootstrap = ( kexists( $config, $image, 'bootstrap' ) && $config->{$image}->{bootstrap} eq 'yes' ) ? 1 : 0;

        if ( $config->{$image}->{build} ne 'yes' ) {
            say 'NO';
            next;
        }

        # assemble data
        $images->{$image} = {
            name => $image,
            tag  => $tag,
            from => {
                name => $config->{$image}->{from},
                tag  => $tag
            },
            bootstrap => $bootstrap
        };
        $images->{$image}->{add}    = $config->{$image}->{add}    if ( kexists( $config, $image, 'add' ) );
        $images->{$image}->{export} = $config->{$image}->{export} if ( kexists( $config, $image, 'export' ) );
        say 'OK';
    }
    return $images;
}

sub _build_images ( $query, @args ) {

    my $image = shift @args;

    unless ($image) {
        say 'Error: no image given';
        return 1;
    }

    my $config       = $query->('config');
    my $builddir     = $query->('builddir');
    my $bashinit     = $query->('bashinit');
    my $data_root    = $query->('data_root');
    my $genesis      = $query->('genesis');
    my $psi          = $query->('psi');
    my $data_images  = $query->('images');
    my $genesis_name = join( '_', $query->('group'), $query->('hostname') );
    my $current_tag  = get_tag;
    my $filter       = sub ( $image_tree_branch, $pending_images, $current_image ) {
        $image_tree_branch->{LEAVES}->{$current_image} = delete $pending_images->{$current_image};
        return $image_tree_branch->{LEAVES};
    };

    print_table( 'Current Tag',        ' ',       ": $current_tag\n" );
    print_table( 'Building Tree for ', "$image ", ": ->\n" );

    my $image_tree = build_image_tree(
        _assemble_images( $config, $current_tag ), $filter, $image    # returns a hash list
    );

    die "ERROR: Not found: $image" unless ($image_tree);

    _update_tree( $image_tree, $builddir );
    _clean_builddir( $image_tree, $builddir );                        # now for all the images we want to build, remove old ones first.

    my @queue   = ();
    my $build_c = sub ($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{name} ) && exists( $branch->[0]->{from} ) );
        return 0;
    };

    foreach my $e ( slice_tree( $image_tree, $build_c ) ) {

        push @queue,
          {
            name        => $e->[0]->{name},
            tag         => $e->[0]->{tag},
            parent_tag  => $e->[0]->{from}->{tag},
            parent_name => $e->[0]->{from}->{name},
            add         => $e->[0]->{add},
            export      => $e->[0]->{export},
            bootstrap   => $e->[0]->{bootstrap},
            bashinit    => $bashinit,
            data_root   => $data_root,
            genesis     => $genesis,
            psi         => $psi,
            path        => join( '', $builddir, '/', $e->[0]->{name}, '/', $e->[0]->{tag} )
          };
    }

    _build_manager(
        sub () { return $query->('state_images') },
        {
            images       => $data_images,
            genesis_name => $genesis_name,
            builddir     => $builddir
        },
        @queue
    );

    return;
}

sub _download ( $source, $target ) {

    print_table( 'Downloading', "$source ", ": $target\n" );
    run_cmd("cd $target && lftp -c mget \"$source\"");

    $source = $1 if ( $source =~ /.*\/([^\/]+)$/x );
    $source =~ s/[*].*//x;
    $source = quotemeta($source);    # gentoo devs are still laughing after they decided that adding '+'
                                     # to image filenames 'just because' was a hilarious idea.
    my $files = get_directory_list($target);

    foreach my $file ( keys $files->%* ) {
        return "$target/$file" if ( $file =~ /^$source/x );
    }
    die 'ERROR: could not download file';
}

sub _extract ( $source, $target, $delete ) {

    print_table( 'Extracting', "$source ", ": $target\n" );
    load_image( $source, $target );
    run_cmd("rm -f $source") if ($delete);
    return;
}

sub _add_images ( $add, $state_images, $path ) {

    # add remaining images
    foreach my $k ( keys( $add->%* ) ) {

        my $source = $add->{$k}->{source};
        my $target = $add->{$k}->{target};

        print_table( 'Adding', "$source ", ": $path$target\n" );

        if ( $source =~ s/^SELF://x ) {
            _extract( "$path$source", "$path$target", 0 );
        }
        elsif ( $source =~ s/^IMAGE://x ) {

            my $images = $state_images->();
            die "ERROR: image $source not found" unless kexists( $images, 'image', $source, 'latest' );
            my $source_path = $images->{image}->{$source}->{latest};

            _extract( $source_path, "$path$target", 0 );
        }
        else {
            _extract( _download( $source, $path ), "$path$target", 1 );
        }
    }
    return;
}

sub _bm_add_root_image ( $task, $state, $paths ) {

    my $builddir    = $paths->{builddir};
    my $parent_name = $task->{parent_name};
    my $parent_tag  = $task->{parent_tag};
    my $name        = $task->{name};
    my $tag         = $task->{tag};

    return 0 unless ( kexists( $task, 'add', $parent_name ) );    # nothing to do

    my $base = kdelete( $task, 'add', $parent_name );

    return 0 if ( kexists( $state, 'snapshots', $parent_tag, $parent_name ) );    # skip if parent is already setup

    my $base_target = $base->{target};
    my $image_path  = "$builddir/$parent_name/$parent_tag";
    my $source      = $base->{source};

    create_btrfs_subvolume( { path => $builddir, target => $parent_name, target_tag => $parent_tag } );

    if ( $source =~ s/^IMAGE://x ) {

        my $images = $state->{images}->();
        die "ERROR: image $source not found" unless kexists( $images, 'image', $source, 'latest' );
        my $source_path = $images->{image}->{$source}->{latest};

        _extract( $source_path, "$image_path$base_target", 0 );
    }
    else {
        _extract( _download( $base->{source}, $image_path ), "$image_path$base_target", 1 );
    }

    return 1;
}

sub _bm_copy_genesis ( $p ) {

    my $path         = $p->{path};
    my $data_root    = $p->{data_root};
    my $state_images = $p->{state_images};
    my $genesis_name = $p->{genesis_name};

    print_table( 'Install genesis', ' ', ': ' );
    my $images = $state_images->();
    die 'ERROR: genesis not found' unless kexists( $images, 'genesis', $genesis_name, 'latest' );
    my $source_path = $images->{genesis}->{$genesis_name}->{latest};

    run_cmd("cp $source_path $path/genesis.img.xz && cd $path && xz -d genesis.img.xz");
    run_cmd("yes | btrfstune -u $path/genesis.img > /dev/null 2>&1 || true");    # a recent change in hetzners rescuecd disallowed mounting the 'same' image twice
    say 'OK';
    return;
}

sub _bm_create_chroot_files ( $p) {

    my $name           = $p->{name};
    my $path           = $p->{path};
    my $bashinit       = $p->{bashinit};
    my $data_root      = $p->{data_root};
    my $genesis        = $p->{genesis};
    my $bootstrap      = $p->{bootstrap};
    my $psi            = $p->{psi};
    my $bashinit2      = join( '', $bashinit, '_2' );
    my $full_bashinit  = join( '', $path, $bashinit );
    my $full_bashinit2 = join( '', $path, $bashinit2 );
    my $full_dataroot  = join( '', $path, $data_root );
    my $full_genesis   = join( '', $path, $genesis );
    my $full_psi       = join( '', $path, $psi );

    print_table( 'Creating chroot entry files', ' ', ': ' );

    my @data_bashinit1 = (
        #
        'error(){',
        'if [ $1 != 0 ]; then',
        'exit $1;',
        'fi',
        '}',
        'source /etc/profile',
        'touch /failflag',
        "rm $bashinit",
        "/bin/bash  --init-file $bashinit2 -i",
        'error $?',
        'exit',

    );
    my @data_bashinit2 = (
        #
        'error(){',
        'if [ $1 != 0 ]; then',
        'exit $1;',
        'fi',
        '}',
        'source /etc/profile',
        'mkdir -p /etc/portage/repos.conf && mkdir -p /var/db/repos/gentoo',
        'if ! test -e /etc/portage/repos.conf/gentoo.conf; then cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf; fi',
        'env-update',
        'export PS1="(chroot) $PS1"',
        "rm $bashinit2",
    );

    push @data_bashinit2, "echo nameserver 8.8.8.8 > /etc/resolv.conf && cd $genesis && ./require.sh" if ($bootstrap);
    push @data_bashinit2, "cd $genesis && ./genesis.pl image build $name";
    push @data_bashinit2, 'error $?';
    push @data_bashinit2, 'rm /failflag';
    push @data_bashinit2, 'exit';

    $_ .= "\n" for @data_bashinit1;
    $_ .= "\n" for @data_bashinit2;

    write_file(
        {
            PATH    => $full_bashinit,
            CONTENT => \@data_bashinit1,
        },
        {
            PATH    => $full_bashinit2,
            CONTENT => \@data_bashinit2,
        }
    );

    say 'OK';
    return;
}

sub _bm_check ( $running, $failed, $finished, $state ) {

    my @pending_running = ();

    while ( my $task = shift $running->@* ) {

        my $name = $task->{name};
        my $tag  = $task->{tag};

        if ( !kexists( $state, 'sessions', $name ) ) {

            print_table( 'Task', "$name ", ': ' );
            my $folder = $state->{snapshots}->{$tag}->{$name}->{path};
            my $files  = get_directory_list($folder);

            if ( exists( $files->{failflag} ) ) {
                push $failed->@*, $task;
                say 'FAILED';
            }
            else {
                push $finished->@*, $task;
                say 'FINISHED';
            }
            _umount_dev($folder);
        }
        else {
            my $folder = $state->{snapshots}->{$tag}->{$name}->{path};
            my $files  = get_directory_list($folder);
            print_table( 'Task', "$name ", ": PAUSED (use 'tmux attach -t $name' to fix)\n" ) if ( exists( $files->{rescueshell} ) );
            push @pending_running, $task;    # still running
        }
    }
    return (@pending_running);
}

sub _bm_remove_failed ( $failed, $task ) {

    # remove entries from the queue that have failed parents
    my $is_failed   = 0;
    my $parent_name = $task->{parent_name};
    my $name        = $task->{name};

    foreach my $failed_task ( $failed->@* ) {

        if ( $failed_task->{name} eq $parent_name ) {
            print_table( 'Task', $name, ": FAILED (parent $parent_name failed)\n" );
            push $failed->@*, $task;
            $is_failed++;
        }
    }
    return $is_failed;
}

sub _bm_start_task ( $task, $state, $paths ) {

    my $state_images = $state->{images};
    my $parent_name  = $task->{parent_name};
    my $parent_tag   = $task->{parent_tag};
    my $name         = $task->{name};
    my $tag          = $task->{tag};

    return 0
      if (!kexists( $state, 'snapshots', $parent_tag, $parent_name )
        || kexists( $state, 'sessions', $parent_name )
        || kexists( $state, 'sessions', $name ) );

#### setup a new session

    create_btrfs_snapshot(
        {
            path       => $paths->{builddir},
            target     => $name,
            target_tag => $tag,
            source     => $parent_name,
            source_tag => $parent_tag,
        }
    );

    my $folder = join( '/', $paths->{builddir}, $name, $tag );

    print_table( 'Preparing environment for', "$name ", ": \n" );
    _add_images( $task->{add}, $state_images, $folder ) if ( exists( $task->{add} ) );
    _bm_copy_genesis(
        {
            path         => $folder,
            data_root    => $task->{data_root},
            state_images => $state_images,
            genesis_name => $paths->{genesis_name}
        }
    );
    _bm_create_chroot_files(
        {
            name      => $name,
            path      => $folder,
            bashinit  => $task->{bashinit},
            data_root => $task->{data_root},
            genesis   => $task->{genesis},
            bootstrap => $task->{bootstrap},
            psi       => $task->{psi},
        }
    );
    _mount_dev($folder);
    print_table( 'Starting Session for', "$name ", ': ' );

    # the sysctl line is needed to build the kernel
    # the setting is not activated again. shouldn't matter for the buildhost though as there is no attack surface.
    run_cmd('sysctl kernel.grsecurity.chroot_deny_mknod=0 > /dev/null 2>&1 || true');
    run_cmd('sysctl net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1 || true');   # disable ipv6 on host system. (prevent dns lookups to return ipv6 addresses)
    if ( $task->{bootstrap} ) {

        say 'BOOTSTRAP';
        run_cmd("chroot $folder /bin/bash --init-file $task->{bashinit}");         # if its the only task, keep it in foreground
    }
    else {
        # the \" is needed for old tmux version (hetzner)
        # unset TMUX is required for nested tmux calls.
        # I need this because the builds can run for hours and the peer is not always my friend :)
        run_cmd("unset TMUX && tmux new-session -d -s $name \"chroot $folder /bin/bash --init-file $task->{bashinit}\"");
        say 'OK';
    }
    return 1;
}

sub _bm_finished ( $finished, $paths ) {

    my $tar_path = $paths->{images};
    my $builddir = $paths->{builddir};

    while ( my $finished_task = shift $finished->@* ) {

        next if ( !exists $finished_task->{export} || !$finished_task->{export} );

        foreach my $tar_name ( keys $finished_task->{export}->%* ) {

            my $root     = $finished_task->{path};
            my $tag      = $finished_task->{tag};
            my $name     = $finished_task->{name};
            my $tar      = $finished_task->{export}->{$tar_name};
            my $source   = join( '', $root, $tar->{source} );
            my $filename = join( '', 'image_', $tar_name );
            my @excludes = ();

            foreach my $exclude ( $tar->{exclude}->@* ) {
                push @excludes, "'$exclude'";
            }

            push @excludes, '\'/etc/shadow.tmp\'';    # hardcoded for a reason
            my $options = join( ' --exclude ', @excludes );
            $options = " --exclude $options";

            if ( $tar->{diff} ) {

                my $parent_name = $finished_task->{parent_name};
                my $parent_tag  = $finished_task->{parent_tag};
                my $real_root   = $root;
                $root   = join( '/', '/tmp/diff', $tar_name );
                $source = join( '',  $root,       $tar->{source} );

                print_table( 'Creating diff', "$parent_name->$tar_name ", ': ' );
                run_cmd( "rm -rf $root", "mkdir -p $root" );
                run_cmd("rsync -aXAm $options --delete --compare-dest=$builddir/$parent_name/$parent_tag $real_root/ $root");

                # idea was nice, but some empty directories are in fact needed for various things to function
                #run_cmd("find $root/ -type d -empty -delete");
                say 'OK';
            }

            print_table( 'Packing', "$name ", ": $tar_name\n" );
            run_cmd("cp -Rfp $root/etc/shadow $root/etc/shadow.tmp && sed -i 's/:[^:]*:/:!:/' $root/etc/shadow") if ( file_exists "$root/etc/shadow" );
            store_image( { source => $source, target => $tar_path, filename => $filename, tag => $tag, options => $options } );
            run_cmd("rm -f $root/etc/shadow && mv $root/etc/shadow.tmp $root/etc/shadow") if ( file_exists "$root/etc/shadow.tmp" );
            run_cmd("rm -rf $root") if ( $tar->{diff} );
        }
    }
    return;
}

sub _build_manager ( $state_images, $paths, @queue ) {

    my @running    = ();
    my @failed     = ();
    my @finished   = ();
    my $bootstrap  = 0;
    my $start_time = time();

    print_table( 'Starting Buildmanager', ' ', ": $start_time\n" );

    while ( $#queue >= 0 || $#running >= 0 ) {

        # sessions and snapshots must not change during an iteration, unless manually updated
        my $state = {
            sessions      => _get_tmux_sessions(),
            snapshots     => get_btrfs_subvolumes( $paths->{builddir} ),
            images        => $state_images,
            pending_queue => [],
        };

        #  mark failed tasks, so we can later remove their child's from the queue
        @running = _bm_check( \@running, \@failed, \@finished, $state );
        _bm_finished( \@finished, $paths );

        if ($bootstrap) {
            say 'exiting';
            last;
        }

        while ( my $task = shift @queue ) {

            next         if _bm_remove_failed( \@failed, $task );
            next         if $bootstrap;                             #  remove all child's from queue if we hit bootstrap before
            $bootstrap++ if ( $task->{bootstrap} );

            if ( _bm_add_root_image( $task, $state, $paths ) ) {
                $state->{snapshots} = get_btrfs_subvolumes( $paths->{builddir} );    # update state so that start_task knows that the parent is setup
            }

            if ( _bm_start_task( $task, $state, $paths ) ) {
                push @running, $task;
            }
            else {
                push $state->{pending_queue}->@*, $task;
            }
        }
        @queue = ( $state->{pending_queue}->@* );

        # mark failed tasks, so we can later remove their childs from the queue
        #$state->{sessions}  = _get_tmux_sessions();
        #$state->{snapshots} = get_btrfs_subvolumes( $paths->{builddir} );
        ###############################

        my $elapsed = _format_time($start_time);
        my $rq      = $#queue + 1;
        my $rr      = $#running + 1;

        print_table( "Runtime: $elapsed", "(queued: $rq, running: $rr) ", ': ' );
        _sleep($SLEEP_CYCLE);
    }
    return;
}

sub _sleep ($count) {

    print 'sleeping ';
    while ( $count != 0 ) {

        print $count;
        sleep 1;
        $count = count_down($count);
    }

    say '';
    return;
}

#######################################################

sub import_build () {

    my $struct = {
        build => {
            CMD  => \&_build_images,
            DESC => 'builds images',
            HELP => [ 'usage:', 'build <image>', 'builds new <image> and rebuilds all its childs', ],
            DATA => {
                builddir     => 'paths data BUILD',
                config       => 'images config',
                bashinit     => 'paths hostos BASHINIT',
                data_root    => 'paths data ROOT',
                images       => 'paths data IMAGES',
                genesis      => 'paths psi GENESIS',
                psi          => 'paths psi ROOT',
                state_images => 'state images',
                group        => 'machine self GROUP',
                hostname     => 'machine self NAMES SHORT'

            }
        }
    };

    return $struct;
}

1;
