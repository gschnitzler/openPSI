package Plugins::Images::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::Images::System::GetImages qw(get_images);
use Plugins::Images::Cmds::Clean qw(import_clean);
use Plugins::Images::Cmds::State qw(import_state);

use PSI::RunCmds qw (run_cmd);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ( $debug, $query ) {

    my $images_path = $query->('images_path');
    #my $uid         = $query->('image_uid');
    my $gid         = $query->('image_gid');

    # setup initial privileges
    # chmod/own bla/* would not work when the directory is empty (which it is during bootstrap)
    # thus the order
    run_cmd("mkdir -p $images_path && chown -R :$gid $images_path && chown root:$gid $images_path && chmod -R 740 $images_path && chmod 770 $images_path");

    return {
        state => {
            images => sub (@arg) {
                return get_images( $images_path, @arg );
            }
        },
        scripts => {},
        macros  => {},
        cmds    => [ import_clean, import_state ]
    };
}

sub import_hooks($self) {
    return {
        name    => 'Images',
        require => [],
        loader  => \&import_loader,
        data    => {
            images_path => 'paths data IMAGES',
            #image_uid   => 'machine self HOST_UID',
            image_gid   => 'machine self USER_ACCOUNTS GROUPS machines GID'
        }
    };
}

