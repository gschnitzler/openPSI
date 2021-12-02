package Plugins::Build::Cmds::Add;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd);
use PSI::Store qw(load_image);
use Tree::Slice qw(slice_tree);
use Tree::Build qw(build_image_tree);

our @EXPORT_OK = qw(import_add);

##########################################################

sub _get_source_tag ( $image_list, $image ) {

    return ( '', '' ) if ( !$image_list || !exists $image_list->{latest} );

    my @l = sort keys $image_list->%*;
    pop @l;    # remove 'latest'
    my $tag    = pop @l;
    my $source = $image_list->{latest};
    return ( $source, $tag );
}

sub _assemble_images ( $config, $tar_images ) {

    my $images = {};

    foreach my $image ( keys $config->%* ) {

        print_table( 'Assembling', "$image ", ': ' );

        if ( $config->{$image}->{build} ne 'yes' ) {
            say 'NO';
            next;
        }

        if ( $config->{$image}->{docker} ne 'yes' ) {
            say 'NO';
            next;
        }

        my ( $source, $tag ) = _get_source_tag( $tar_images->{image}->{$image}, $image );

        # assemble data
        $images->{$image} = {
            name   => $image,
            tag    => $tag,
            source => $source,
            from   => {
                name => $config->{$image}->{from},
                tag  => ''
            },
        };

        # root images
        if ( kexists( $config, $image, 'add', $config->{$image}->{from} ) ) {

            my $real_source = $config->{$image}->{add}->{ $config->{$image}->{from} }->{source};

            if ( $real_source =~ /^IMAGE:(.*)/x ) {

                my $parent = $1;
                $images->{$image}->{from}->{name} = $parent;

                # add the parent image if its not there
                if ( !exists( $images->{$parent} ) ) {
                    my ( $parent_source, $parent_tag ) = _get_source_tag( $tar_images->{image}->{$parent}, $image );

                    $images->{$parent} = {
                        name   => $parent,
                        tag    => $parent_tag,
                        source => $parent_source,
                        from   => {
                            name => 'ROOT',
                            tag  => ''
                        },
                    };
                }
            }
            else {
                # remove images that have unsuitable parents right away
                delete $images->{$image};
                say 'NO';
                next;
            }
        }
        say 'OK';
    }
    return $images;
}

sub _prepare_tree ( $config, $images, $base ) {

    my $filter = sub ( $image_tree_branch, $pending_images, $current_image ) {

        my $self       = $pending_images->{$current_image};
        my $tag        = $self->{tag};
        my $parent     = $image_tree_branch->{name};
        my $parent_tag = $image_tree_branch->{tag};

        if ($parent_tag) {
            if ($tag) {
                die "ERROR: parent $parent:$parent_tag is newer than me $current_image:$tag" if ( $tag < $parent_tag );
                $self->{from}->{tag} = $parent_tag;
            }
            else {
                say "WARNING: no source: $current_image";
            }
        }
        else {
            say "WARNING: no source: $parent, parent of $current_image";
        }

        $image_tree_branch->{LEAVES}->{$current_image} = delete $pending_images->{$current_image};
        return $image_tree_branch->{LEAVES};
    };

    print_table( 'Building Tree', ' ', ": ->\n" );
    my $image_tree = build_image_tree(
        _assemble_images( $config, $images ), $filter, $base    # returns a hash list
    );

    die "ERROR: $base not found" unless ($image_tree);

    # find missing sources;
    my $cond_imgtree = sub ($branch) {
        return 1
          if ( ref $branch->[0] eq 'HASH'
            && exists $branch->[0]->{tag}
            && exists $branch->[0]->{source}
            && !$branch->[0]->{tag}
            && !$branch->[0]->{source} );
        return 0;
    };

    my $fail = 0;
    foreach my $failed ( slice_tree( $image_tree, $cond_imgtree ) ) {
        say 'ERROR: required source missing: ', $failed->[0]->{name};
        $fail++;
    }

    print_table( 'Branch', ' ', ': ' );
    die 'ERROR: branch incomplete' if ($fail);
    say 'complete';

    return $image_tree;
}

sub _check_parent ( $image_tree ) {

    # check if parent image exists in docker repo
    # note that this is based on locally stored images, not the docker repository.
    # the chain is only complete if the images on disk are.
    foreach my $root ( keys $image_tree->%* ) {

        next if ( $image_tree->{$root}->{from}->{name} eq 'ROOT' );

        my $p           = $image_tree->{$root}->{from}->{name};
        my $t           = $image_tree->{$root}->{from}->{tag};
        my $cond_parent = sub ($branch) {
            return 1
              if ( ref $branch->[0] eq 'HASH'
                && kexists( $branch->[0], 'from', 'name' )
                && kexists( $branch->[0], 'from', 'tag' )
                && $branch->[0]->{from}->{name} eq $p
                && $branch->[0]->{from}->{tag} eq $t );
            return 0;
        };

        my $hit = slice_tree( $image_tree, $cond_parent );

        # as $image_tree only contains the latest images, there can only be one hit
        # slice_tree returns an array, shich is assigned in scalar context to $hit, thus:
        die "ERROR: parent $p:$t is missing in docker repository" unless ( $hit == 1 );
    }
    return $image_tree;
}

sub _clean_docker_repository ( $image_tree, $docker_tree ) {

    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;

    my $cond_image_tree = sub ($branch) {
        return 1
          if ( ref $branch->[0] eq 'HASH'
            && exists $branch->[0]->{tag}
            && exists $branch->[0]->{source}
            && exists $branch->[0]->{name}
            && exists $branch->[0]->{from} );
        return 0;
    };

    my $image_tree_list = {};
    $image_tree_list->{ $_->[0]->{name} } = $_->[0]->{tag} for slice_tree( $image_tree, $cond_image_tree );

    # docker wants us to remove all child images by hand
    my $cond_docker_tree = sub ($branch) {
        return 1
          if ( ref $branch->[0] eq 'HASH'
            && exists $branch->[0]->{REPOSITORY}
            && exists $branch->[0]->{TAG}
            && exists $image_tree_list->{ $branch->[0]->{REPOSITORY} }
            && $image_tree_list->{ $branch->[0]->{REPOSITORY} } eq $branch->[0]->{TAG} );
        return 0;
    };

    my @stripped = ();
    push @stripped, $_->[0] for slice_tree( $docker_tree, $cond_docker_tree );
    _delete_images(@stripped);

    return;
}

sub _delete_images (@branches) {

    my $delete = {};
    my $cond   = sub ($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists $branch->[0]->{NAME} );
        return 0;
    };

    foreach my $branch (@branches) {
        $delete->{ $_->[0]->{NAME} } = 1 for ( slice_tree( { anything => $branch }, $cond ) );
    }

    my $string = join( ' ', keys( $delete->%* ) );
    return unless ($string);
    print_table( 'Deleting Docker Images', ' ', ": $string\n" );
    run_cmd("docker rmi $string > /dev/null 2>&1");
    return;
}

sub _create_docker_repository ( $image_tree, $docker_path, $query ) {

    $docker_path          = join( '/', $docker_path, 'btrfs', 'subvolumes' );
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;

    my $cond_image_tree = sub ($branch) {
        return 1
          if ( ref $branch->[0] eq 'HASH'
            && exists $branch->[0]->{tag}
            && exists $branch->[0]->{source}
            && exists $branch->[0]->{name}
            && exists $branch->[0]->{from} );
        return 0;
    };

    for my $entry ( slice_tree( $image_tree, $cond_image_tree ) ) {

        my $image       = $entry->[0];
        my $name        = $image->{name};
        my $tag         = $image->{tag};
        my $source      = $image->{source};
        my $parent      = $image->{from}->{name};
        my $parent_tag  = $image->{from}->{tag};
        my $parent_from = join( ':', $parent, $parent_tag );
        my $nametag     = join( ':', $name, $tag );
        my $tmp_root    = '/tmp/unpack';

        if ( $parent eq 'ROOT' ) {

            print_table( 'Adding', "$nametag ", ": /\n" );
            run_cmd "cat $source | docker import - $nametag > /dev/nul 2>&1";
            next;
        }

        print_table( 'Adding', "$nametag ", ": (from: $parent_from)\n" );

        my $target = $query->(
            'find_image',
            {
                path           => $docker_path,
                container_name => $name,
                parent_image   => $parent_from,
                token          => $nametag,
            }
        );

        print_table( 'Populating Layer ', "$target ", ': ' );

        # we cant use load_image/tar directly here.
        # the latest layer may contain symlinks that were directories on the layer below.
        # this happens for example, when a config directory in /etc/ is mapped to /data/config/
        # tar has a few shotgun options (like recursive-unlink), sadly they do not do.
        # so we temporarily unpack the archive and intervene
        my $tmp_dir = join( '/', $tmp_root, $name );
        run_cmd( "rm -rf $tmp_dir", "mkdir -p $tmp_dir" );
        load_image( $source, $tmp_dir );

        # mtab file is a symlink to proc created by docker. so we ignore that
        run_cmd(
            "rm -f $tmp_dir/etc/mtab",
            "for i in \$(cd $tmp_dir && find etc/ -type l); do rm -rf $target/\$i; done",    # remove all items that are symlinks in our source in the target
            "cp -fpa $tmp_dir/* $target/", "rm -rf $tmp_dir"
        );
        say 'OK';

        print_table( 'Committing to Docker', "$nametag ", ': ' );
        run_cmd "docker commit --change 'CMD [\"/data/config/init.pl\"]' $name $nametag";    # TODO hardcoded path.
                                                                                             # say 'OK'; docker commit outputs a hash

        print_table( 'Removing Container', $name, ': ' );
        run_cmd("docker rm $name > /dev/null 2>&1");
        say 'OK';
    }
    return;
}

sub _import_images ( $query, @args ) {

    my $base = shift @args;
    die 'ERROR: no image given' unless $base;

    my $images      = $query->('images');
    my $config      = $query->('config');
    my $docker_path = $query->('docker_path');
    my $docker_tree = $query->('docker_tree');
    my $image_tree  = _check_parent( _prepare_tree( $config, $images, $base ) );

    _clean_docker_repository( $image_tree, $docker_tree );
    _create_docker_repository( $image_tree, $docker_path, $query );

    return;
}

sub import_add () {

    my $struct = {
        docker => {
            add => {
                CMD  => \&_import_images,
                DESC => 'imports latest images to docker',
                HELP => [ 'usage:', 'docker add <image>', 'adds latest images to docker repo' ],
                DATA => {
                    images      => 'state images',
                    find_image  => 'state docker_find_image',
                    config      => 'images config',
                    docker_path => 'paths data DOCKER',
                    docker_tree => 'state docker_image_tree',
                }
            }
        }
    };

    return $struct;
}

1;
