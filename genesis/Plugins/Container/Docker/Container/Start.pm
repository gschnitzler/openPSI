package Plugins::Container::Docker::Container::Start;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);

our @EXPORT_OK = qw(create_container_start_script);

#########################################################

sub _get_latest_version ( $list, $image ) {

    my @versions = ();
    foreach my $entry ( $list->@* ) {
        push @versions, $entry->{TAG} if ( exists $entry->{REPOSITORY} && exists( $entry->{TAG} ) && $entry->{REPOSITORY} eq $image );
    }
    @versions = sort @versions;
    return pop @versions;
}

sub _get_arg_string($config) {
    return join( ' ', $config->{ARGS}->@* ) if ( exists( $config->{ARGS} ) );
    return '';
}

sub _get_tag_string ( $docker_images, $image ) {
    my $tag = _get_latest_version( $docker_images, $image );
    die "ERROR: image not found $image" unless ($tag);
    return $tag;
}

sub _create_directories ( $path ) {

    my $data_path          = $path->{DATA};
    my @create_directories = ();

    foreach my $k ( keys $path->%* ) {
        my $p = $path->{$k};
        push @create_directories, "mkdir -p $p && chmod 555 $p || true";
    }

    # unmount before possible recursive chown
    push( @create_directories, "umount -lf $data_path > /dev/null 2>&1 || true" );
    return @create_directories;
}

sub _create_map_directories ( $root_path, $paths ) {

    my @create_directories = ();

    push @create_directories, "rm -rf $root_path/* || true";    # clean it out
    foreach my $k ( keys $paths->%* ) {
        push @create_directories, "mkdir -p $root_path/$k && chmod 555 $root_path/$k || true";
        push @create_directories, "mkdir -p $paths->{$k} || true";                               # also create source folder (put don't change permissions),
                                                                                                 # as this container might be started before the other
    }

    return @create_directories;
}

sub _create_mount ( $images, $container_name, $data_path ) {

    return unless ( kexists( $images, $container_name, 'latest' ) );
    my $cur_data_img     = $images->{$container_name}->{latest};
    my $data_path_parent = $data_path;
    $data_path_parent =~ s/[^\/]+$//x;

    return (
        "rm -f $data_path_parent/data.img.xz > /dev/null 2>&1",
        "cp -f $cur_data_img $data_path_parent/data.img.xz",
        "cd $data_path_parent && rm -f data.img && xz -d data.img.xz",
        "mount $data_path_parent/data.img /$data_path",
    );
}

sub create_docker_run ( $container_name, $docker, $container_path, $args, $tag ) {

    my $options           = $docker->{OPTS};
    my $host_path         = $docker->{PATHS};
    my $image             = $docker->{IMAGE};
    my $docker_run_string = 'docker run';
    my @volumes           = ();
    my $add_string        = sub(@add_to_string) {
        $docker_run_string .= join( ' ', '', @add_to_string );
        return;
    };

    if ( exists $docker->{MAP} ) {
        foreach my $k ( keys $docker->{MAP}->%* ) {
            push @volumes, join( ':', $docker->{MAP}->{$k}, join( '/', $container_path->{MAPPED}, $k ), 'rw' );
        }
    }

    foreach my $k ( keys $host_path->%* ) {
        die "ERROR: no mapping for $k" unless exists $container_path->{$k};
        push @volumes, join( ':', $host_path->{$k}, $container_path->{$k}, 'rw' );
    }

    # well, docker did it again... in their last version, they decided to refuse underscores in hostnames.
    # now hold your horses: someone who stumbled upon a RFC from the 70ies opened a ticket suggesting 'it might break shit deep down'.
    # thing is... well, up until then, it did not break anybody's shit.
    # anyway, the kiddies all went 'wooooo rfc' and some guy was found, who moments ago read 'regex for dummies' and implemented that.
    # its just the same shit like with that python mysql library that did the same stupid thing, all over again.
    # why the fuck do they have to do that? the dns server is perfectly able to handle that. I mean its 2016.. helloooo~
    # so, well.. lets just replace the underscore and build up rage whenever we enter a container and see the hostname nobody cares about missing a character.
    ## turns out, services (like apache) do use the containers hostname... as a workaround, I had the dnsmasq config generator also add all the hostnames without the underscore.
    ## when the docker boys decide to undo their mistake in a year, remove that again.

    my $docker_sucks_so_here_is_an_underscore_free_hostname = $container_name;
    $docker_sucks_so_here_is_an_underscore_free_hostname =~ s/_//g;

    $add_string->($options);
    $add_string->( '-i', '--net=none', '--restart=no', '-d=true' );
    $add_string->( '--hostname', $docker_sucks_so_here_is_an_underscore_free_hostname );
    $add_string->( '--name',     $container_name );
    $add_string->( '-v',         $_ ) for (@volumes);
    $add_string->( '-t',         "$image:$tag" );
    $add_string->($args) if $args;
    $add_string->( '>', '/dev/null 2>&1' );

    return $docker_run_string;
}
#########################################################

sub create_container_start_script ( $config, $docker_images, $images, $running_container ) {

    my $container_name     = $config->{NAME};
    my @create_directories = _create_directories( $config->{DOCKER}->{PATHS} );
    my @create_map_directories =
      ( kexists( $config, 'DOCKER', 'MAP' ) ) ? _create_map_directories( $config->{DOCKER}->{PATHS}->{MAPPED}, $config->{DOCKER}->{MAP}, ) : ();
    my @mount_data        = ( exists $images->{data} ) ? _create_mount( $images->{data}, $container_name, $config->{DOCKER}->{PATHS}->{DATA} ) : ();
    my $docker_run_string = create_docker_run(
        #
        $container_name,
        $config->{DOCKER},
        $config->{CONTAINER}->{PATHS},
        _get_arg_string($config),
        _get_tag_string( $docker_images, $config->{DOCKER}->{IMAGE} ),
    );

    return {
        create_dirs       => \@create_directories,
        create_map_dirs   => \@create_map_directories,
        mount_data        => \@mount_data,
        docker_run        => $docker_run_string,
        running_container => $running_container,

    };
}

1;
