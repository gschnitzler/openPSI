package Plugins::HostOS::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::HostOS::State::HostOS  qw(get_hostos_state);
use Plugins::HostOS::Macros::HostOS qw(get_hostos_macros);

use Plugins::HostOS::Cmds::State          qw(import_state);
use Plugins::HostOS::Cmds::Config         qw(import_config);
use Plugins::HostOS::Cmds::Switch         qw(import_switch);
use Plugins::HostOS::Cmds::Update         qw(import_update);
use Plugins::HostOS::Cmds::SysUsers       qw(import_sysusers);
use Plugins::HostOS::Cmds::PackageVersion qw(import_packageversion);
use Plugins::HostOS::Cmds::Chroot         qw(import_chroot);

our @EXPORT_OK = qw(import_hooks);

############## frontend

sub import_loader ( $debug, $query ) {

    my $state_param = {
        fstab_file   => $query->('fstab_file'),
        release_file => $query->('release_file')
    };

    return {
        state   => get_hostos_state($state_param),
        scripts => $query->('scripts'),
        macros  => get_hostos_macros,
        cmds    => [

            # Cmds::Config needs to know if the respective modules should be loaded
            # this is by no means a nice solution, but i could not come up with a better way to
            # implement the all statement, so services are passed

            import_config( $query->('services') ),    # let the config plugin decide what to load
            import_state,
            import_switch,
            import_update,
            import_sysusers,
            import_packageversion,
            import_chroot,
        ]
    };
}

sub import_hooks ($self) {
    return {
        name    => 'HostOS',
        require => [ 'Images', 'Network' ],
        loader  => \&import_loader,
        data    => {
            release_file => 'paths hostos RELEASE',
            fstab_file   => 'paths hostos FSTAB',
            scripts      => 'hostos Scripts',
            services     => 'machine self COMPONENTS SERVICE',
        }
    };
}

1;

