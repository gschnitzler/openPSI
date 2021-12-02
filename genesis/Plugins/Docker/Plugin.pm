package Plugins::Docker::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Docker::Libs::GetImageLayer qw(find_image_layer);
use Plugins::Docker::Libs::GetImage qw(get_docker_image_tree get_docker_image_list);

use Plugins::Docker::Cmds::Update qw(import_update);
use Plugins::Docker::Cmds::State qw(import_state);
use Plugins::Docker::Cmds::Clean qw(import_clean);
use Plugins::Docker::Cmds::PackageVersion qw(import_packageversion);

our @EXPORT_OK = qw(import_hooks);

#########

sub import_loader ( $debug, $query ) {

    my $state = {
        docker_image_tree => \&get_docker_image_tree,
        docker_image_list => \&get_docker_image_list,
        docker_find_image => \&find_image_layer,
    };

    return {
        state   => $state,
        scripts => {},
        macros  => {},
        cmds    => [ import_update, import_state, import_clean, import_packageversion ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Docker',
        require => ['Images'],
        loader  => \&import_loader,
        data    => {

        }
    };
}
