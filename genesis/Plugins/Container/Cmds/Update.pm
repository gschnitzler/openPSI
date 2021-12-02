package Plugins::Container::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use File::Path qw(remove_tree make_path);
use PSI::RunCmds qw(run_cmd);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw (import_update);

####################################################

sub _update ( $tarball, $target_path ) {

    {
        local ( $?, $! );
        print_table( 'Cleaning', $target_path, ': ' );
        make_path $target_path;
        remove_tree( $target_path, { keep_root => 1 } );
        say 'OK';
    }
    print_table( 'Installing Data ', $target_path, ': ' );
    run_cmd "tar xpf $tarball --xattrs -C $target_path > /dev/null";
    say 'OK';

    return;
}

sub _update_data ( $query, @args ) {

    my $container     = shift @args;
    my $images        = $query->('images');
    my $container_cfg = $query->('container');

    my $cf = _get_container( $container_cfg, $container );
    unless ($cf) {
        say 'ERROR: unknown container';
        return 1;
    }

    unless ( kexists( $images, 'data', $container, 'latest' ) ) {
        say 'ERROR: no image found';
        return 1;
    }

    my $tarball     = $images->{data}->{$container}->{latest};
    my $target_path = $cf->{DOCKER}->{PATHS}->{DATA};

    _update( $tarball, $target_path );

    return;
}

sub _update_pdata ( $query, @args ) {

    my $container     = shift @args;
    my $images        = $query->('images');
    my $container_cfg = $query->('container');

    my $cf = _get_container( $container_cfg, $container );
    unless ($cf) {
        say 'ERROR: unknown container';
        return 1;
    }

    unless ( kexists( $images, 'pdata', $container, 'latest' ) ) {
        say 'ERROR: no image found';
        return 1;
    }

    my $tarball     = $images->{pdata}->{$container}->{latest};
    my $target_path = $cf->{DOCKER}->{PATHS}->{PERSISTENT};

    _update( $tarball, $target_path );

    return;
}

sub _get_container ( $config, $container ) {

    return unless ($container);
    my ( $arg_name, $arg_tag ) = split( /_/, $container );
    return if ( !$arg_name || !$arg_tag || !kexists( $config, $arg_name, $arg_tag ) );
    return ( $config->{$arg_name}->{$arg_tag}->{config} );
}

sub import_update () {

    my $struct = {
        update => {
            container => {
                pdata => {
                    CMD  => \&_update_pdata,
                    DESC => 'Updates Container pdata',
                    HELP => [
                        'usage:',
                        'update container pdata <container>',
                        'installs updated pdata for container <container> from tarball',
                        'tarball must not me an image'
                    ],
                    DATA => {
                        images    => 'state images',
                        container => 'container'
                    }
                },
                data => {
                    CMD  => \&_update_data,
                    DESC => 'Updates Container data',
                    HELP => [
                        'usage:',
                        'update container data <container>',
                        'installs updated data for container <container> from tarball',
                        'tarball must not me an image'
                    ],
                    DATA => {
                        images    => 'state images',
                        container => 'container'
                    }
                }
            }
        },
    };

    return $struct;
}

1;
