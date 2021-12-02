package Plugins::HostOS::Macros::HostOS;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(get_hostos_macros);

sub get_hostos_macros() {

    return {
        install => {
            system => {
                MACRO => [
                    'mount target',    #
                    'update clean_target',
                    'update root',
                    'unmount target',
                ],
                HELP => ['installs root fs'],
                DESC => 'installs root fs',
            },
        },
        bootstrap => {
            node => {
                MACRO => [ 'pull bootstrap image_hostos §source', 'pull bootstrap image_boot §source', 'bootstrap target system' ],
                HELP  => ['setup new node'],
                DESC  => 'setup new node',
            },
            target => {
                system => {
                    MACRO => [
                        'install system',    # need to 'unmount system' in parent shell manually
                        'mount bootstrap',
                        'SAVECHROOT',
                        'enter chroot macro',
                        'CONTINUE',
                        'init grub_install',
                        'update bootfiles',
                        'clean host config',
                        'generate host config all',
                        'install host config',
                        'update fstab',
                        'config sshd',
                        'add users',
                        'system passwd',
                    ],
                    HELP => ['configures target system'],
                    DESC => 'configures target system'
                }
            },
        },
        config => {
            target => {
                system => {
                    MACRO => [
                        'mount system',    # need to 'unmount system' in parent shell manually
                        'SAVECHROOT',
                        'enter chroot macro',
                        'CONTINUE',
                        'clean host config',
                        'generate host config all',
                        'install host config',
                        'update fstab',
                        'config sshd',
                        'add users',
                        'system passwd',
                    ],
                    HELP => ['configures target system'],
                    DESC => 'configures target system'
                }
            },
        },
        update => {
            system => {
                MACRO => [
                    'pull normal image_hostos §machine',
                    'pull normal image_boot §machine',
                    'update local'
                ],
                HELP => ['pulls updates from §machine and installs them'],
                DESC => 'pulls updates from §machine and installs them'
            },
            local => {
                MACRO => [
                    'install system',
                    'update boot',
                    'config target system',
                ],
                HELP => ['updates from latest local images'],
                DESC => 'updates from latest local images'
            }
        },
    };
}

1;
