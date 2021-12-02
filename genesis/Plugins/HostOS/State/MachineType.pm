package Plugins::HostOS::State::MachineType;

use ModernStyle;
use Exporter qw(import);

#use PSI::Parse::File qw(read_files);
#use PSI::Console qw(print_table);

# Export
our @EXPORT_OK = qw(get_machine_type);

sub get_machine_type ( $print=0 ) {

    my $type = 'metal';

    # there is only metal with gentoo-sources
    # $print = 1 if $print && $print eq 'print';

    # print_table( 'Determining machine type ', ' ', ': ' ) if $print;

    # my $scsi = read_files('/proc/scsi/scsi');

    # foreach my $line ( $scsi->{CONTENT}->@* ) {

    #     if ( $line =~ m/Vendor:.*(VBOX)/x ) {
    #         $type = 'vbox';
    #         last;
    #     }
    #     if ( $line =~ m/Vendor:.*(QEMU)/x ) {
    #         $type = 'kvm';
    #         last;
    #     }
    # }

    # say $type if $print;

    return $type;
}
1;
