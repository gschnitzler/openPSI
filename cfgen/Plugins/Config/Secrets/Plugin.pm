package Plugins::Config::Secrets::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Check qw(dir_exists);
use IO::Templates::Read qw(read_templates);
use PSI::RunCmds qw(run_system);
use Plugins::Config::Secrets::Cmds::Manage qw(import_manage);

our @EXPORT_OK = qw(import_hooks);

#####################

sub import_loader ( $debug, $query ) {

    my $config_path    = $query->('CONFIG_PATH');
    my $default_cfmeta = '{ \'./*\' => { CHMOD => \'400\'}}';

    # don't read secrets if there are none
    mkdir $config_path or print '' unless ( dir_exists $config_path );
    run_system "echo \"$default_cfmeta\"> $config_path/.cfmeta" unless -e "$config_path/.cfmeta";
    my $secrets = read_templates( $debug, $config_path );

    return {
        state => {
            secrets => sub () {
                return dclone $secrets;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => [ import_manage() ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Secrets',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

