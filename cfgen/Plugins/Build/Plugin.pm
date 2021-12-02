package Plugins::Build::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Build::Cmds::Build qw(import_build);
use Plugins::Build::Cmds::List qw(import_list);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ( $debug, $query ) {

    return {
        state   => {},
        scripts => {},
        macros  => {},
        cmds    => [ import_build, import_list ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Build',
        require => [ 'Accounts', 'Bootstrap', 'Cluster', 'Container', 'Genesis', 'HostOS', 'Images', 'Paths', 'Roles', 'Secrets', 'Services' ],
        loader  => \&import_loader,
    };
}

