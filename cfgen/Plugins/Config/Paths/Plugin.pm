package Plugins::Config::Paths::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);
use Carp;

use IO::Config::Read qw(read_config load_config);
use IO::Config::Check qw(check_config);

our @EXPORT_OK = qw(import_hooks);

#####################

my $check = {

    '*' => { '*' => [qr/^(.+)/x], }
};

sub _map_container_paths ($config) {

    my $root_path = $config->{data}->{ROOT};
    my $mappings  = $config->{container}->{MAPPINGS};

    confess 'ERROR: incomplete container path config' if ( !$root_path || scalar keys $mappings->%* == 0 );
    my $paths = {};

    foreach my $k ( keys $mappings->%* ) {
        $paths->{$k} = join( '/', $root_path, $mappings->{$k} );
    }
    return sub () {
        return $paths;
    };
}

sub _map_container_host_paths ($config) {

    my $root_path = $config->{data}->{ROOT};
    my $mappings  = $config->{container}->{MAPPINGS};
    my $prefix    = $config->{container}->{HOST}->{PREFIX};

    die 'ERROR: incomplete container host path config' if ( !$root_path || scalar keys $mappings->%* == 0 || !$prefix );

    return sub (@args) {

        my ( $container_name, $container_tag ) = @args;
        unless ($container_name) {
            say 'WARNING: no container name given, returning \'STUB\'';
            say 'WARNING: if you see this error when running \'list template variables, you are save to ignore it\'';
            $container_name = 'STUB';
        }
        unless ($container_tag) {
            say 'WARNING: no container tag given, returning \'STUB\'';
            say 'WARNING: if you see this error when running \'list template variables, you are save to ignore it\'';
            $container_tag = 'STUB';
        }

        my $paths = {};
        foreach my $k ( keys $mappings->%* ) {
            $paths->{$k} = join( '/', $root_path, $prefix, $container_name, $container_tag, $mappings->{$k} );
        }
        return $paths;

    };
}

sub import_loader ( $debug, $query ) {

    my $config_path = $query->('CONFIG_PATH');
    my $paths = load_config( read_config( $debug, $config_path ) );

    check_config(
        $debug,
        {   name       => 'Paths',
            config     => $paths,
            definition => $check
        }
    );

    return {
        state => {
            paths => sub () {
                return dclone $paths;
            },
            map_container_paths      => _map_container_paths($paths),
            map_container_host_paths => _map_container_host_paths($paths),
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Paths',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

