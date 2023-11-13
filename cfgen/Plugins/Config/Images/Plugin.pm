package Plugins::Config::Images::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo               qw(kexists);
use PSI::Parse::Packages qw(assemble_packages);
use Tree::Merge          qw(add_tree);

use IO::Config::Cache   qw(read_cache write_cache);
use IO::Config::Check   qw(check_config);
use IO::Config::Read    qw(read_config load_config);
use IO::Templates::Read qw(read_templates);

our @EXPORT_OK = qw(import_hooks);

my $check = {
    root      => [qr/^([.]\/.*)/x],
    scripts   => [qr/^([.]\/.*)/x],
    templates => [qr/^([.]\/.*)/x],
    from      => [qr/^(.+)/x],
    groups    => { '*' => [qr/^(\d+)/x], },
    build     => [qr/^\s*(yes|no)/x],
    docker    => [qr/^\s*(yes|no)/x],         # only images that have this set to yes are included in docker images.
    bootstrap => [qr/^\s*(yes|no)/x],         # lets Build know it has to alter its behaviour
    users     => {
        '*' => {
            uid   => [qr/^(\d+)/x],
            gid   => [qr/^(\d+)/x],
            home  => [qr/^(\/.*)/x],
            shell => [qr/^(\/.*)/x],
        }
    },
    add => {
        '*' => {
            source => [qr/^(.+)/x],
            target => [qr/^(\/.*)/x],
        }
    },
    export => {
        '*' => {
            source  => [qr/^(\/.*)/x],
            exclude => [qr/(.+)/x],
            diff    => [qr/([10])/x]
        }
    }
};

sub _packages ( $debug, $pkg_dir ) {

    # we only want packages, the other files (like config) are dropped
    my $packages          = {};
    my $packages_andfiles = assemble_packages( $debug, read_templates( $debug, $pkg_dir ) );
    $packages->{emerge_pre}  = delete $packages_andfiles->{emerge_pre};
    $packages->{emerge_pkg}  = delete $packages_andfiles->{emerge_pkg};
    $packages->{emerge_post} = delete $packages_andfiles->{emerge_post};
    return $packages;
}

sub _guids ($config) {

    my @guids = ();

    ############## order matters #########################
    # upstream images might have users/groups created.
    # remove them and replace em as specified in the image

    # removing uids
    if ( exists( $config->{users} ) ) {

        my $users = $config->{users};
        foreach my $user ( keys $users->%* ) {
            push @guids, "userdel $user > /dev/null 2>&1 || true";
        }
    }

    # removing gids
    if ( exists( $config->{groups} ) ) {

        my $groups = $config->{groups};
        foreach my $group ( keys $groups->%* ) {
            push @guids, "groupdel $group > /dev/null 2>&1 || true";
        }
    }

    #########################################################

    # adding gids
    if ( exists( $config->{groups} ) ) {

        my $groups = $config->{groups};
        foreach my $group ( keys $groups->%* ) {
            push @guids, "groupadd -g $groups->{$group} $group";
        }
    }

    # adding uids
    if ( exists( $config->{users} ) ) {

        my $users = $config->{users};
        foreach my $user ( keys $users->%* ) {

            my $uid = $users->{$user};
            push @guids, "useradd -u $uid->{uid} -g $uid->{gid} -d $uid->{home} -s $uid->{shell} $user";
        }
    }
    return @guids;
}

sub _transform_buildscripts ( $debug, $path, $config ) {

    my $build       = $config->{build};
    my $from        = $config->{from};
    my $pkg_dir     = $config->{root};
    my $scripts_dir = $config->{scripts};

    die 'ERROR: build flag not set' unless ($build);
    return {}                       unless ( $build eq 'yes' );

    $pkg_dir =~ s/^[.]//x;
    $pkg_dir = join( '', $path, $pkg_dir );

    my $scripts = {};
    if ($scripts_dir) {
        $scripts_dir =~ s/^[.]//x;
        $scripts_dir = join( '', $path, $scripts_dir );
        $scripts     = read_templates( $debug, $scripts_dir );

    }
    add_tree( $scripts, _packages( $debug, $pkg_dir ) );

    # merge guids into pre
    my @guids = _guids($config);
    $scripts->{emerge_pre}->{CONTENT} = [ @guids, $scripts->{emerge_pre}->{CONTENT}->@* ] if kexists( $scripts, 'emerge_pre', 'CONTENT' );

    return $scripts;
}

sub _read_config_from_source ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $paths       = $query->('paths');

    # not the best solution to first find and load the configfiles, then evaluate the 'root' parameter
    # and import the templates, this time removing the configfile
    # would be nicer to just have a 'definition.cf' file in every folder, read in the directory and assemble as needed.
    # this is just the result of quick merging old code after redesign
    # anyway it works
    # 13.11.2023: mhh. 'definition.cf' sounds just like cfmeta. try to decypher the meaning of the above and utilize cfmeta
    my $config    = load_config( read_config( $debug, $config_path ) );
    my $scripts   = {};
    my $templates = {};

    foreach my $image ( keys $config->%* ) {

        my $image_def = $config->{$image};
        check_config(
            $debug,
            {
                name       => $image,
                config     => $image_def,
                definition => $check,
            }
        );

        next unless ( $image_def->{build} eq 'yes' );

        # note: the sole purpose of this was for kernel config to be accessible to the template substuitutions later on.
        # therefore, this termplate gets converted into a string and newlines reapplied
        # the downside of this is, that each kernel image configfile is now stored twice in the genesis config
        # (as template and as filled substitution)
        # anyway, it works
        if ( exists( $image_def->{templates} ) ) {
            my $template_path = $image_def->{templates};
            $template_path =~ s/^[.]//x;
            $template_path = join( '', $config_path, $template_path );
            my $temp = read_templates( $debug, $template_path );

            foreach my $k ( keys $temp->%* ) {
                $templates->{$image}->{$k} = join( "\n", $temp->{$k}->{CONTENT}->@* );
            }
        }
        $scripts->{$image} = _transform_buildscripts( $debug, $config_path, $image_def );
        delete $scripts->{$image} if ( scalar keys $scripts->{$image}->%* == 0 );
    }
    return ( $config, $scripts, $templates, $paths );
}

sub import_loader ( $debug, $query ) {

    my $cache_path      = $query->('CACHE');
    my $cache_config    = 'config.cfgen';
    my $cache_scripts   = 'scripts.cfgen';
    my $cache_templates = 'templates.cfgen';
    my $cache_paths     = 'paths.cfgen';

    my ( $config, $scripts, $templates, $paths ) = read_cache( $debug, $cache_path, $cache_config, $cache_scripts, $cache_templates, $cache_paths );

    if ( !$config || !$scripts || !$templates || !$paths ) {
        ( $config, $scripts, $templates, $paths ) = _read_config_from_source( $debug, $query );
        write_cache(
            $debug,
            $cache_path,
            {
                $cache_config    => $config,
                $cache_scripts   => $scripts,
                $cache_templates => $templates,
                $cache_paths     => $paths
            }
        );
    }

    return {
        state => {
            images => sub () {
                return dclone {
                    config    => $config,
                    scripts   => $scripts,
                    templates => $templates,
                    paths     => $paths,
                };
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks ($self) {
    return {
        name    => 'Images',
        require => ['Paths'],
        loader  => \&import_loader,
        data    => {
            CONFIG_PATH => 'CONFIG_PATH',
            CACHE       => 'CACHE',
            paths       => 'state map_container_paths'
        }
    };
}

