package Plugins::HostOS::Macros::HostOS;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(get_hostos_macros);

sub get_hostos_macros() {

    return {
        install => {
            system => {
                HELP  => ['installs root fs'],
                DESC  => 'installs root fs',
                MACRO => [                       #
                    'mount target',
                    'update clean_target',
                    'update root',
                    'unmount target',
                ],
            },
        },
        bootstrap => {
            node => {
                HELP  => ['setup new node'],
                DESC  => 'setup new node',
                MACRO => [                       #
                    'pull bootstrap image_hostos §source',
                    'bootstrap target system'
                ],
            },
            target => {
                system => {
                    HELP  => ['configures target system'],
                    DESC  => 'configures target system',
                    MACRO => [                               #
                        'install system',                    # need to 'unmount system' in parent shell manually
                        'mount bootstrap',
                        'SAVECHROOT',
                        'enter chroot macro',
                        'CONTINUE',
                        'config system'
                    ],
                }
            },
        },
        config => {
            system => {
                HELP  => ['configures system'],
                DESC  => 'configures system',
                MACRO => [                        #
                    'update boot',
                    'clean host config',
                    'generate host config all',
                    'install host config',
                    'update fstab',
                    'config sshd',
                    'add users',
                    'system passwd',

                ],
            },
            target => {
                system => {
                    HELP  => ['configures target system'],
                    DESC  => 'configures target system',
                    MACRO => [                               #
                        'mount system',                      # need to 'unmount system' in parent shell manually
                        'SAVECHROOT',
                        'enter chroot macro',
                        'CONTINUE',
                        'config system'
                    ],
                }
            },
        },
        update => {
            system => {
                HELP  => ['pulls updates from §machine and installs them'],
                DESC  => 'pulls updates from §machine and installs them',
                MACRO => [                                                    #
                    'pull normal image_hostos §machine',
                    'update local'
                ],
            },
            local => {

                HELP  => ['updates from latest local images'],
                DESC  => 'updates from latest local images',
                MACRO => [                                                    #
                    'install system',
                    'config target system',
                ],
            }
        },
    };
}

1;
