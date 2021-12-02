package Plugins::Container::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);

use Plugins::Container::System::GetContainer qw(get_docker_container);
use Plugins::Container::Macros::Container qw(get_container_macros);

use Plugins::Container::Cmds::Enter qw(import_enter);
use Plugins::Container::Cmds::State qw(import_state);
use Plugins::Container::Cmds::Config qw(import_config);
use Plugins::Container::Cmds::Manage qw(import_manage);
use Plugins::Container::Cmds::Update qw(import_update);
use Plugins::Container::Cmds::Backup qw(import_backup);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ( $debug, $query ) {

    my $service       = $query->('services');
    my $enable_backup = 0;
    $enable_backup = 1 if ( kexists( $service, 'backup', 'ENABLE' ) && $service->{backup}->{ENABLE} eq 'yes' );

    return {
        state  => { docker_container => \&get_docker_container, },
        macros => get_container_macros,
        cmds   => [
            #
            import_state,
            import_config,
            import_manage,
            import_enter,
            import_update,
            import_backup($enable_backup),
        ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Container',
        require => [ 'Docker', 'Network' ],
        loader  => \&import_loader,
        data    => { services => 'machine self COMPONENTS SERVICE' }
    };
}

1;
