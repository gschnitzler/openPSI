package Plugins::Config::Services::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Templates::Read qw(read_templates);
use IO::Config::Cache qw(read_cache write_cache);
use IO::Config::Check qw(check_config);
use IO::Config::Read qw(read_config load_config);

use Tree::Merge qw (override_tree);
use IO::Templates::Read qw(convert_meta_structure);
use IO::Templates::Parse qw(get_directory_tree_from_templates);
use IO::Templates::Meta::Parse qw(convert_meta_paths);
use IO::Templates::Meta::Apply qw(apply_meta);

our @EXPORT_OK = qw(import_hooks);

####################

my $check = {
    '*' => {
        REQUIRE              => [qr/^(.+)/x],
        SCRIPTS              => [ qr/^(.+)/x, 'dircheck' ],
        TEMPLATES            => [ qr/^(.+)/x, 'dircheck' ],
        TEMPLATE_PERMISSIONS => [qr/^(.+)/x],                 # useful when sourcing in external templates. to add LOCATION or alter UID/GID
    }
};

sub _require ( $toload, $loaded, $debug, $service_name, $config_path, $required ) {

    foreach my $required_service ( $required->@* ) {

        unless ( exists( $loaded->{$required_service} ) ) {
            push $toload->@*, $service_name;
            return $required;
        }
    }
    $loaded->{$service_name} = 1;
    return [];
}

sub _templates ( $debug, $service_name, $config_path, $template_path ) {

    # templates might already be loaded (because _require pushed it back onto the queue)
    return $template_path if ( ref $template_path eq 'HASH' );
    return read_templates( $debug, join( '', $config_path, $template_path =~ s/^[.]//rx ) ) if $template_path =~ /^[.]/;
    return read_templates( $debug, $template_path );    # for absolute paths
}

sub _read_config_from_source ( $debug, $query ) {
    my $config_path = $query->('CONFIG_PATH');
    my $services    = check_config(
        $debug,
        {
            name       => 'Services',
            config     => load_config( read_config( $debug, $config_path ) ),
            definition => $check,
        }
    );

    my @services_toload = keys( $services->%* );
    my $loaded_services = {};
    my $dispatch        = {
        REQUIRE   => sub (@args) { _require( \@services_toload, $loaded_services, @args ) },
        SCRIPTS   => \&_templates,
        TEMPLATES => \&_templates,
    };

    while ( my $service_name = shift @services_toload ) {

        my $service              = $services->{$service_name};
        my $template_permissions = exists( $service->{TEMPLATE_PERMISSIONS} ) ? delete $service->{TEMPLATE_PERMISSIONS} : undef;

        foreach my $section ( keys $service->%* ) {
            $service->{$section} = $dispatch->{$section}->( $debug, $service_name, $config_path, $service->{$section} );
        }

        override_tree( $service->{TEMPLATES},
            convert_meta_structure( apply_meta( get_directory_tree_from_templates( $service->{TEMPLATES} ), convert_meta_paths($template_permissions) ) ) )
          if ($template_permissions);
        
    }
    return $services;
}

sub import_loader ( $debug, $query ) {

    my $cache_path     = $query->('CACHE');
    my $cache_services = 'services.cfgen';
    my $services       = read_cache( $debug, $cache_path, $cache_services );

    if ( !$services ) {
        $services = _read_config_from_source( $debug, $query );
        write_cache( $debug, $cache_path, { $cache_services => $services, } );
    }

    return {
        state => {
            services => sub () {
                return dclone $services;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Services',
        require => [],
        loader  => \&import_loader,
        data    => {
            CONFIG_PATH => 'CONFIG_PATH',
            CACHE       => 'CACHE'
        }
    };
}

