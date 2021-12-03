package Plugins::HostOS::Cmds::Switch;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Plugins::HostOS::Libs::Parse::Grub qw(read_grub write_grub);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(import_switch);

###################################

sub _switch_system ( $query, @ ) {

    my $chroot        = $query->('state chroot');
    my $mtype         = $query->('state machine_type');
    my $target_system = $query->('state root target');
    my $grub_f        = $query->('grub');
    my $grub_template = $query->('grub_template');

    if ( $chroot eq 'yes' ) {
        say 'can\'t use switch while in chroot.';
        return 1;
    }

    my $fullsys = join( '-', $target_system, $mtype );

    print_table 'Switching System', ' ', ": \n";

    my $grub = read_grub($grub_f);
#say Dumper $grub;
    die 'ERROR: switch to nonexisting system'
        unless ( exists( $grub->{$fullsys} ) );

    $grub->{current} = $fullsys;
#say Dumper $grub;

    write_grub(
        {   template => $grub_template,
            grub     => $grub,
            path     => $grub_f,
        }
    );

    say "System was switched! Restart the Machine to boot into $target_system.";
    return;
}

sub import_switch () {

    my $struct = {
        switch => {
            system => {
                CMD  => \&_switch_system,
                DESC => 'switches between installed systems',
                HELP => ['used after a system update, to switch to the newly installed system'],
                DATA => {
                    state => {
                        chroot       => 'state chroot',
                        machine_type => 'state machine_type',
                        root         => { target => 'state root_target', },
                    },
                    grub          => 'paths hostos GRUB',
                    grub_template => 'service grub TEMPLATES'

                }
            }
        }
    };

    return $struct;
}
1;
