package Plugins::Copy::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Copy::Cmds::Etl qw(import_etl);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ($debug, $query) {

    return {
        state   => {},
        scripts => {},
        macros  => {},
        cmds    => [ import_etl ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Copy',
        require => ['Container'],
        loader  => \&import_loader,
        data    => {}
    };
}

