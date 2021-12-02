package Plugins::Build::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Build::Cmds::Build qw(import_build);
use Plugins::Build::Cmds::Clean qw(import_clean);
use Plugins::Build::Cmds::Save qw(import_save);
use Plugins::Build::Cmds::Add qw(import_add);

our @EXPORT_OK = qw(import_hooks);

#########

sub import_loader ( $debug, $query ) {

    my $scripts->{image} = $query->('scripts');
    my $image_config     = $query->('config');
    my $macros           = {};

    # build the macros here, the build command just launches genesis with the macros in chroot

    foreach my $k ( keys $image_config->%* ) {

        my $image = $image_config->{$k};
        $macros->{image}->{build}->{$k} = {
            MACRO => [],
            DESC  => "$k build macro",
            HELP  => ["$k build macro"]
        };

        my $macro_ref = $macros->{image}->{build}->{$k}->{MACRO};

        push $macro_ref->@*, "image $k emerge_pre";
        push $macro_ref->@*, "image $k emerge_pkg";
        push $macro_ref->@*, "image $k emerge_post";
        push $macro_ref->@*, 'save package version';
        push $macro_ref->@*, 'image os_base cleanup';
    }

    return {
        state   => {},
        scripts => $scripts,
        macros  => $macros,

        # build generates its commands on the fly
        cmds => [ import_build, import_clean, import_add, import_save ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Build',
        require => [ 'Images', 'Docker' ],
        loader  => \&import_loader,
        data    => {
            scripts => 'images scripts',
            config  => 'images config',

        }
    };
}
