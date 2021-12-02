package Plugins::Deploy::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Deploy::Cmds::Pull qw(import_pull);
use Plugins::Deploy::Cmds::Push qw(import_push);
use Plugins::Deploy::Cmds::Stage qw(import_stage);
use Plugins::Deploy::Cmds::Remote qw(import_remote);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ($debug, $query) {

    return {
        state   => {},
        scripts => {},
        macros  => {},
        cmds    => [ import_remote, import_pull, import_stage, import_push ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Deploy',
        require => ['Images'],
        loader  => \&import_loader,
        data    => {}
    };
}

