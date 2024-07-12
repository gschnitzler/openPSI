package Plugins::HostOS::Cmds::Switch;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console    qw(print_table);
use PSI::RunCmds    qw(run_open run_cmd);
use PSI::Parse::Dir qw(get_directory_list);
our @EXPORT_OK = qw(import_switch);

###################################

sub _parse_efibootmgr() {

    my $cf = {};

    for my $line ( run_open('efibootmgr') ) {
        $line =~ s/\t.*//;    # with version 18 they introduced this: https://github.com/rhboot/efibootmgr/commit/8ec3e9dedb3cb62f19847794012420b90f475398
                              # bananas that they did not hide this behind a switch. RH is so full of it. so lets remove the added line noise.
        my ( $key, @values ) = split /\s+/, $line;    # remove padding
        $key =~ s/://;
        $cf->{$key} = join ' ', @values;
    }

    $cf->{BootOrder} = [ split /,/, delete $cf->{BootOrder} ];

    for my $key ( keys $cf->%* ) {

        if ( $key =~ /^Boot(\d+)\*/ ) {
            my $entry = $1;
            next unless $entry;
            $cf->{Entries}->{$entry} = delete $cf->{$key};    # multiple entries might have the same name
        }
    }

    return $cf;
}

sub _add_efi_entries ( $efi, $disk, $target_system ) {

    my $path = "\\$target_system\.efi";

    for my $entry ( keys $efi->{Entries}->%* ) {
        my $name = $efi->{Entries}->{$entry};

        next if $name ne $target_system;
        print_table 'Deleting EFI Entry', $target_system, ': ';

        # efibootmgr does not care about reachable paths etc. if an entry already exists, it just silently overrides it. maybe.
        # better delete and readd
        run_cmd("efibootmgr -b $entry -B $entry --quiet");
        say 'OK';
    }

    print_table 'Add EFI Entry', $target_system, ': ';
    run_cmd("efibootmgr --create --disk $disk --part 2 --label '$target_system' --loader '$path' --unicode --quiet");
    say 'OK';

    return;
}

sub _update_efi_bootorder ( $efi, $boot_first_name, $target_system ) {
    my @neworder            = ();
    my $boot_first_entry    = '';
    my $target_system_entry = '';

    print_table 'Update EFI Bootorder', $target_system, ': ';
    for my $entry ( keys $efi->{Entries}->%* ) {
        my $name = $efi->{Entries}->{$entry};

        # find first entry
        if ( $name =~ /^\Q$boot_first_name/ ) {
            $boot_first_entry = $entry;
            $boot_first_name  = $name;
            delete $efi->{Entries}->{$entry};
        }

        if ( $name =~ /^\Q$target_system/ ) {
            $target_system_entry = $entry;
            $target_system       = $name;
            delete $efi->{Entries}->{$entry};
        }
    }

    die 'Target System not found' unless $target_system_entry;

    push @neworder, $boot_first_entry if $boot_first_entry;
    push @neworder, $target_system_entry;

    for my $e ( $efi->{BootOrder}->@* ) {
        push @neworder, $e if exists( $efi->{Entries}->{$e} );
    }
    my $order = join( ',', @neworder );
    run_cmd("efibootmgr --bootorder $order --quiet");
    say 'OK';
    return;
}

sub _switch_system ( $query, @ ) {

    my $chroot         = $query->('state chroot');
    my $current_system = $query->('state root current');
    my $target_system  = $query->('state root target');
    my $boot_first     = $query->('boot_first');
    my $boot_disk      = $query->('boot_disk');

    if ( $chroot eq 'yes' ) {
        say 'can\'t use switch while in chroot.';
        return 1;
    }

    print_table 'Switching System', ' ', ": $current_system -> $target_system\n";    # remove n and say old -> new system

    # seems like the unmount of target system unmounts efivarfs aswell. at least on buildhost after unmount bootstrap.
    my $efivar_path = '/sys/firmware/efi/efivars';
    my $list        = get_directory_list($efivar_path);

    if ( scalar keys $list->%* == 0 ) {
        run_cmd("mount -t efivarfs efivarfs $efivar_path");
    }

    # there are no checks here...
    _add_efi_entries( _parse_efibootmgr(), $boot_disk, $target_system );             # check if boot entries are there, if not add
    _update_efi_bootorder( _parse_efibootmgr(), $boot_first, $target_system );

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
                        chroot    => 'state chroot',
                        root      => {
                            target  => 'state root_target',
                            current => 'state root_current'
                        },
                    },
                    boot_first => 'machine self RAID BOOT_FIRST',
                    boot_disk  => 'machine self RAID DISK1',
                }
            }
        }
    };

    return $struct;
}
1;
