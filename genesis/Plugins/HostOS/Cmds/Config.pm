package Plugins::HostOS::Cmds::Config;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Path qw(remove_tree make_path);

use Plugins::HostOS::Libs::Parse::Archive qw(gen_archive);
use Plugins::HostOS::Libs::Parse::Dnsmasq qw(gen_dnsmasq);
use Plugins::HostOS::Libs::Parse::DHCP qw(gen_dhcp);
use Plugins::HostOS::Libs::Parse::Strongswan qw(gen_strongswan);
use Plugins::HostOS::Libs::Parse::Network qw(gen_network);
use Plugins::HostOS::Libs::Parse::Grub qw(gen_grub);
use Plugins::HostOS::Libs::Parse::Dio qw(gen_dio);
use Plugins::HostOS::Libs::Parse::Ssmtp qw(gen_ssmtp);
use Plugins::HostOS::Libs::Parse::SSH qw(gen_ssh);
use Plugins::HostOS::Libs::Parse::Smartd qw(gen_smartd);
use Plugins::HostOS::Libs::Parse::Backup qw(gen_backup);
use Plugins::HostOS::Libs::Parse::Syslog qw(gen_syslog);
use Plugins::HostOS::Libs::Parse::Fail2Ban qw(gen_fail2ban);
use Plugins::HostOS::Libs::Parse::Wireguard qw(gen_wireguard);
use Plugins::HostOS::Libs::Parse::Prometheus qw(gen_prometheus);

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd);
use IO::Templates::Write qw(write_templates);
use IO::Config::Check qw(dir_exists);

use Tree::Slice qw(slice_tree);
use Tree::Merge qw(clone_tree);

our @EXPORT_OK = qw(import_config);

#######################################################

sub _generate_config ( $modules, $query, @args ) {

    my $local_path       = $query->('paths local_config');
    my @filled_templates = ();

    foreach my $module ( $modules->@* ) {
        push @filled_templates, $module->( $query, @args );
    }

    # write out after all are generated
    foreach my $tree (@filled_templates) {
        write_templates( $local_path, $tree, 1 );
    }
    return;
}

sub _clean_local_dir ( $query, @args ) {

    my $path = $query->('paths local_config');

    print_table 'Cleaning local config: ', $path, ': ';

    {
        local ( $!, $? );
        if ( dir_exists($path) ) {
            remove_tree( $path, { keep_root => 1 } );
        }
        else {
            make_path($path);
        }
    }
    say 'OK';

    return;
}

sub _install_local_dir ( $query, @args ) {

    my $from = $query->('paths local_config');
    my $to   = '/';
    print_table 'Installing Config: ', $from, ": $to\n";

    # dircopy( $from, $to ) or die "installation failed";
    # and once more, a perl module proves to be less reliable than their system counterpart.
    # dircopy failed to copy (some) files to /
    run_cmd("cp -Rfp $from/* $to");

    return unless ( dir_exists '/runonce' );

    print_table 'Executing config scripts: ', '/runonce', ": \n";
    run_cmd('cd /runonce && for i in $(ls); do ./$i; done');
    remove_tree('/runonce');
    return;
}

###########################################

sub import_config ($config) {

    my $struct = {
        clean => {
            host => {
                config => {
                    CMD  => \&_clean_local_dir,
                    DESC => 'removes local host config',
                    HELP => ['removes the generated local host config. use this before generating new config'],
                    DATA => {
                        paths => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                    }
                }
            }
        },
        install => {
            host => {
                config => {
                    CMD  => \&_install_local_dir,
                    DESC => 'installs previously generated local config to host',
                    HELP => ['installs previously generated local config to host. use this after generating new config'],
                    DATA => {
                        paths => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                    }
                }
            }
        }
    };

    my $services = {
        dnsmasq => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_dnsmasq ], @arg ) },
            DESC   => 'Generate dnsmasq config',
            HELP   => ['Generate dnsmasq config'],
            DATA   => {
                paths  => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config => {
                    dnsmasq => {
                        dhcp             => 'machine self COMPONENTS SERVICE dhcp',    # dhcp hostnames need to be incorporated into hosts config
                        nodes            => 'machine nodes',
                        container        => 'machine self COMPONENTS CONTAINER',
                        container_config => 'container',
                        network          => 'state network',
                        name             => 'machine self NAMES SHORT',
                        fullname         => 'machine self NAMES FULL',
                    }
                },
                templates     => { dnsmasq => 'service dnsmasq TEMPLATES' },
                scripts       => { dnsmasq => 'service dnsmasq SCRIPTS' },
                substitutions => { dnsmasq => { state => { network => 'state network' } } }
            }
        },
        dhcp => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_dhcp ], @arg ) },
            DESC   => 'Generate dhcp config',
            HELP   => ['Generate dhcp config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config        => { dhcp         => { dhcp => 'machine self COMPONENTS SERVICE dhcp' } },
                templates     => { dhcp         => 'service dhcp TEMPLATES' },
                scripts       => { dhcp         => 'service dhcp SCRIPTS' },
                substitutions => { dhcp         => {} }
            },
        },
        network => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_network ], @arg ) },
            DESC   => 'Generate network config',
            HELP   => ['Generate network config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { network      => 'service network TEMPLATES' },
                substitutions => {
                    network => {
                        services   => 'machine self COMPONENTS SERVICE',
                        domainname => 'machine self DNS DOMAIN',
                        state      => { network => 'state network' }
                    }
                }
            }
        },
        grub => {
            ENABLE => 'no',
            CMD    => sub (@arg) { _generate_config( [ \&gen_grub ], @arg ) },
            DESC   => 'Generate grub config',
            HELP   => ['Generate grub config'],
            DATA   => {
                paths  => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config => {
                    grub => {
                        grubfile     => 'paths hostos GRUB',
                        machine_type => 'state machine_type',
                        root         => 'machine self RAID DISK1',
                    }
                },
                templates => { grub => 'service grub TEMPLATES' },
            }
        },
        strongswan => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_strongswan ], @arg ) },
            DESC   => 'Generate ipsec config',
            HELP   => ['Generate ipsec config'],
            DATA   => {
                paths  => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config => {
                    strongswan => {
                        nodes        => 'machine nodes',
                        name         => 'machine self NAMES SHORT',
                        roadwarriors => 'machine self USER_ACCOUNTS USERS',
                        config       => 'machine self COMPONENTS SERVICE strongswan'
                    }
                },
                templates     => { strongswan => 'service strongswan TEMPLATES' },
                scripts       => { strongswan => 'service strongswan SCRIPTS' },
                substitutions => { strongswan => { state => { network => 'state network' }, } }
            }
        },
        dio => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_dio ], @arg ) },
            DESC   => 'Generate dio config',
            HELP   => ['Generate dio config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config        => { dio          => {}, },
                templates     => { dio          => 'service dio TEMPLATES' },
                scripts       => { dio          => 'service dio SCRIPTS' },
                substitutions => { dio          => {} }
            }
        },
        archive => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_archive ], @arg ) },
            DESC   => 'Generate archive config',
            HELP   => ['Generate archive config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config        => { archive      => {}, },
                templates     => { archive      => 'service archive TEMPLATES' },
                scripts       => { archive      => 'service archive SCRIPTS' },
                substitutions => { archive      => 'machine self COMPONENTS SERVICE archive' }
            }
        },
        ssmtp => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_ssmtp ], @arg ) },
            DESC   => 'Generate ssmtp config',
            HELP   => ['Generate ssmtp config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { ssmtp        => 'service ssmtp TEMPLATES' },
                substitutions => { ssmtp        => {} }
            }
        },
        syslog => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_syslog ], @arg ) },
            DESC   => 'Generate syslog config',
            HELP   => ['Generate syslog config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { syslog       => 'service syslog TEMPLATES' },
                config        => { syslog       => 'machine self COMPONENTS SERVICE syslog' },
                substitutions => { syslog       => {} }
            }
        },
        fail2ban => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_fail2ban ], @arg ) },
            DESC   => 'Generate fail2ban config',
            HELP   => ['Generate fail2ban config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { fail2ban     => 'service fail2ban TEMPLATES' },
                config        => { fail2ban     => 'machine self COMPONENTS SERVICE fail2ban' },
                substitutions => { fail2ban     => {} }
            }
        },
        wireguard => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_wireguard ], @arg ) },
            DESC   => 'Generate wireguard config',
            HELP   => ['Generate wireguard config'],
            DATA   => {
                paths     => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates => { wireguard    => 'service wireguard TEMPLATES' },
                config    => {
                    wireguard => {
                        wireguard => 'machine self COMPONENTS SERVICE wireguard',
                        users     => 'machine self USER_ACCOUNTS USERS',
                        host_name => 'machine self NAMES FULL',
                        network   => 'state network',
                    }
                },
                substitutions => { wireguard => {} }
            }
        },
        smartd => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_smartd ], @arg ) },
            DESC   => 'Generate smartd config',
            HELP   => ['Generate smartd config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                scripts       => { smartd       => 'service smartd SCRIPTS' },
                templates     => { smartd       => 'service smartd TEMPLATES' },
                substitutions => { smartd       => {} }
            },
        },
        ssh => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_ssh ], @arg ) },
            DESC   => 'Generate ssh config',
            HELP   => ['Generate ssh config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                config        => { ssh          => 'machine self COMPONENTS SERVICE ssh HOSTKEYS' },
                templates     => { ssh          => 'service ssh TEMPLATES' },
                scripts       => { ssh          => 'service ssh SCRIPTS' },
                substitutions => { ssh          => {} }
            },
        },
        backup => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_backup ], @arg ) },
            DESC   => 'Generate backup config',
            HELP   => ['Generate backup config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { backup       => 'service backup TEMPLATES' },
                scripts       => { backup       => 'service backup SCRIPTS' },
                substitutions => { backup       => {} }
            },
        },
        prometheus => {
            ENABLE => 'yes',
            CMD    => sub (@arg) { _generate_config( [ \&gen_prometheus ], @arg ) },
            DESC   => 'Generate prometheus config',
            HELP   => ['Generate prometheus config'],
            DATA   => {
                paths         => { local_config => 'paths data LOCAL_HOST_CONFIG' },
                templates     => { prometheus   => 'service prometheus TEMPLATES' },
                scripts       => { prometheus   => 'service prometheus SCRIPTS' },
                substitutions => { prometheus   => {} }
            }
        },
    };

    my @all_modules = ();
    foreach my $service_name ( keys $config->%* ) {

        next if ( !kexists( $config, $service_name, 'ENABLE' ) || $config->{$service_name}->{ENABLE} ne 'yes' );
        die "ERROR: Service configation for $service_name does not have a handler" unless exists( $services->{$service_name} );

        $struct->{generate}->{host}->{config}->{$service_name} = $services->{$service_name};
        push @all_modules, $services->{$service_name}->{CMD};
    }

    $struct->{generate}->{host}->{config}->{all} = {
        CMD => sub (@args) {

            for my $f (@all_modules) {
                $f->(@args);
            }
            return;
        },
        DESC => 'Generates all host configs',
        HELP => ['Generates all host configs'],
        DATA => {}                                # see below
    };

    # for better maintenance, combine all individual DATA queries for the 'all' call here automatically
    my $cond = sub ($b) {
        return 1 if ( ref $b->[0] eq 'HASH' && exists( $b->[0]->{DATA} ) );
        return 0;
    };

    my @data = ();
    push @data, $_->[0]->{DATA} foreach ( slice_tree( $struct->{generate}->{host}->{config}, $cond ) );

    $struct->{generate}->{host}->{config}->{all}->{DATA} = clone_tree(@data);

    return $struct;
}
1;
