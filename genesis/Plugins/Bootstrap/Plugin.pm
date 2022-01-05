package Plugins::Bootstrap::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(import_hooks);

############## frontend

sub import_loader ( $debug, $query ) {

    my $paths_psi_genesis = $query->('genesis');

    my $macros = {
        bootstrap => {
            machine => {
                MACRO => [
                    'push bootstrap bootstrap §machine',
                    'remote bootstrap §machine \'cd /tmp && rm -f bootstrap.tar.xz && mv bootstrap*.tar.xz bootstrap.tar.xz && tar xf bootstrap.tar.xz && ./mkfs.sh && ./mkfolder.sh && ./mount_data.sh\'',
                    'push bootstrap genesis §machine',
                    # mount -t efivarfs efivarfs /sys/firmware/efi/efivars
                    "remote bootstrap §machine 'cd /tmp && ./install_genesis.sh && cd $paths_psi_genesis && rm -rf /tmp/bootstrap* && rm -rf /tmp/*.sh && source /etc/profile && ./require.sh'",
                ],
                HELP => ['prepare a rescuecd booted linux box for genesis, requires §machine'],
                DESC => 'prepare a rescuecd booted linux box for genesis, requires §machine',
            },
        }
    };

    return {
        state   => {},
        scripts => {},
        macros  => $macros,
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Bootstrap',
        require => ['Deploy'],
        loader  => \&import_loader,
        data    => { genesis => 'paths psi GENESIS', }
    };
}

1;
