package Plugins::Container::Cmds::Config;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Path qw(remove_tree make_path);
use Readonly;

use InVivo qw(kexists);
use IO::Templates::Parse qw(check_and_fill_template);
use IO::Templates::Write qw(write_templates);
use IO::Config::Check qw(dir_exists);
use Tree::Slice qw(slice_tree);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd);

our @EXPORT_OK = qw(import_config);

Readonly my $MASK => oct(7777);    # to satisfy perl critic, oct() is used instead of 07777

###################

sub _generate_container_config ( $query, @args ) {

    my $container         = shift @args;
    my $substitutions     = $query->('substitutions');
    my $local_config_path = $query->('paths config');
    my $config            = $query->('config');
    my $cond              = sub ($b) {
        return 1 if ( ref $b->[0] eq 'HASH' && exists $b->[0]->{CHMOD} && exists $b->[0]->{CONTENT} );
        return 0;
    };

    _clean_dir( $query, $container );

    foreach my $container_cfg ( _get_container( $config, $container ) ) {

        my ( $container_name, $container_tag ) = split( /_/, $container_cfg->{NAME} );
        my $container_templates = $config->{$container_name}->{$container_tag}->{templates};

        foreach my $entry ( slice_tree( $container_templates, $cond ) ) {
            my $h    = $entry->[0];
            my $path = $entry->[1];

            # relative path in $local_config_path is enough
            #$h->{LOCATION} = join( '/', '', $container_name, $container_tag, $path->@* );
            $h->{LOCATION} = join( '/', $path->@* );
            $h->{CONTENT}  = check_and_fill_template( $h->{CONTENT}, $substitutions );
        }
        my $local_container_path = join( '/', $local_config_path, $container_name, $container_tag );
        print_table 'Writing Config: ', "$local_container_path", ': ';
        write_templates( $local_container_path, $container_templates, 0 );
        say 'OK';
    }
    return;
}

sub _clean_dir ( $query, @args ) {

    my $container = shift @args;
    my $path      = $query->('paths config');
    my ( $arg_name, $arg_tag ) = ( '', '' );

    if ($container) {
        ( $arg_name, $arg_tag ) = split( /_/, $container );
        if ( !$arg_name || !$arg_tag ) {
            say "ERROR: Invalid container $container";
            return;
        }
    }

    $path = join( '/', $path, $arg_name, $arg_tag ) if ($container);
    print_table 'Cleaning config from: ', $path, ': ';
    {
        local ( $?, $! );
        make_path $path unless ( dir_exists $path );
        remove_tree( $path, { keep_root => 1 } );
    }

    say 'OK';
    return;
}

sub _clean_production_dir ( $query, @args ) {

    my $container = shift @args;
    my $config    = $query->('config');

    foreach my $container_cf ( _get_container( $config, $container ) ) {

        my $delpath = $container_cf->{DOCKER}->{PATHS}->{CONFIG};
        print_table 'Cleaning config from: ', $delpath, ': ';

        unless ( dir_exists $delpath ) {
            say 'Skipped (No production config)';
            next;
        }
        {
            local ( $?, $! );
            remove_tree( $delpath, { keep_root => 1 } );
        }

        say 'OK';
    }
    return;
}

sub _install_dir ( $query, @args ) {

    my $container = shift @args;
    my $config    = $query->('config');
    my $from      = $query->('paths config');

    foreach my $container_cf ( _get_container( $config, $container ) ) {

        my $from_path = join( '/', $from, split( /_/, $container_cf->{NAME} ) );
        my $to_path   = $container_cf->{DOCKER}->{PATHS}->{CONFIG};

        print_table 'Installing Config: ', $to_path, ': ';

        unless ( dir_exists $from_path ) {
            say 'Skipped (No local config)';
            next;
        }

        # well. of course dircopy does not preserve permissions. I hate this fucking module
        #dircopy( $from_path, $to_path ) or die 'installation failed';
        # do not remove the to_path dir, as it is mounted in docker
        run_cmd "mkdir -p $to_path > /dev/null 2>&1 || true";
        run_cmd "cp -Rfp $from_path/* $to_path";
        run_cmd "chmod --reference $from_path $to_path";
        run_cmd "chown --reference $from_path $to_path";

        my $chmod = sprintf '%o', ( stat($from_path) )[2] & $MASK;
        my $uid   = ( stat($from_path) )[4];
        my $gid   = ( stat($from_path) )[5];
        chmod oct($chmod), $to_path or die 'chmod failed';
        chown $uid, $gid, $to_path or die 'chown failed';

        say 'OK';
    }

    return;
}

sub _get_container ( $config, $container ) {

    my @containers = ();
    my ( $arg_name, $arg_tag ) = ( '', '' );

    if ($container) {

        ( $arg_name, $arg_tag ) = split( /_/, $container );
        if ( !$arg_name || !$arg_tag || !kexists( $config, $arg_name, $arg_tag ) ) {
            say "ERROR: container $container not found";
            return;
        }
    }

    # containers to start
    foreach my $container_name ( keys $config->%* ) {

        next if ( $arg_name && $container_name ne $arg_name );

        foreach my $container_tag ( keys $config->{$container_name}->%* ) {

            next if ( $arg_tag && $container_tag ne $arg_tag );
            my $container_cfg = $config->{$container_name}->{$container_tag}->{config};

            #$container_cfg->{NAME} = $container_name;
            push @containers, $container_cfg;
        }
    }

    return @containers;
}

sub import_config () {

    my $struct = {};

    $struct->{clean}->{local}->{container}->{config} = {
        CMD  => \&_clean_dir,
        DESC => 'removes local container config',
        HELP => [ 'removes the generated local container config.', 'usage: clean local container config [container_name]' ],
        DATA => {
            paths => { config => 'paths data LOCAL_CONTAINER_CONFIG' },

        }
    };

    $struct->{clean}->{production}->{container}->{config} = {
        CMD  => \&_clean_production_dir,
        DESC => 'removes production container config',
        HELP => [
            'removes the installed production container config.',
            'be aware that this might affect running containers',
            'best practice is to stop containers beforehand.',
            'usage: \'clean production container config [container_name]\'',
            'if container_name is omitted, config directory of all registered containers is removed.'
        ],
        DATA => { config => 'container' }
    };

    $struct->{install}->{container}->{config} = {
        CMD  => \&_install_dir,
        DESC => 'installs previously generated local container config to production containers',
        HELP => [
            'installs previously generated local container config to production containers. use this after generating new config',
            'best practice is to clean the production config and stopping the containers before doing so.',
            'usage: \'install container config [container_name]\'',
            'if container_name is omitted, all (generated) container config will be installed'
        ],
        DATA => {
            paths  => { config => 'paths data LOCAL_CONTAINER_CONFIG', },
            config => 'container'
        }
    };
    $struct->{generate}->{container}->{config} = {
        CMD  => \&_generate_container_config,
        DESC => 'Generate Container config',
        HELP => [
            'Generate Container config', 'usage:', 'generate container config [container]', 'if [container] is given, only generate config for that container'
        ],
        DATA => {
            paths         => { config => 'paths data LOCAL_CONTAINER_CONFIG' },
            config        => 'container',
            substitutions => {}
        }
    };

    return $struct;
}

1;
