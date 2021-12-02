package Plugins::HostOS::Libs::Parse::Fstab;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use InVivo qw(kexists);
use PSI::Parse::File qw(parse_file write_file);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(read_fstab write_fstab);

Readonly my $FSTAB_ENTRY     => qr{[^\s]+};
Readonly my $FSTAB_DELIMETER => qr{\s+};
Readonly my $FSTAB_LINE      => qr{
        ^($FSTAB_ENTRY)$FSTAB_DELIMETER
        ($FSTAB_ENTRY)$FSTAB_DELIMETER
        ($FSTAB_ENTRY)$FSTAB_DELIMETER
        ($FSTAB_ENTRY)$FSTAB_DELIMETER
        ($FSTAB_ENTRY)$FSTAB_DELIMETER
        ($FSTAB_ENTRY)
        }x;

sub _struct_fstab ( $struct, $heap, $flush_heap, $line ) {

    return if ( $line =~ /\s*\#/x );

    # on rescue cds, we don't have /dev/md?, so we will be a little more general
    if ( $line =~ $FSTAB_LINE ) {

        my ( $device, $mountpoint, $fs, $fs_flags, $dump, $pass ) = ( $1, $2, $3, $4, $5, $6 );
        $struct->{$mountpoint} = {
            device   => $device,
            fs       => $fs,
            fs_flags => $fs_flags,
            dump     => $dump,
            pass     => $pass
        };
        if ( $struct->{$mountpoint}->{fs_flags} =~ /subvol=([^,\s]+)/x ) {
            $struct->{$mountpoint}->{subvol} = $1;
        }
    }
    return;
}

#############################################################################

sub write_fstab ( $p ) {

    my $fstab      = $p->{fstab};
    my $fstab_f    = $p->{path};
    my $disk1      = $p->{disk1};
    my $disk2      = $p->{disk2};
    my $raid_level = $p->{raid_level};
    my $ff         = [];

    print_table( 'Generating fstab ', ' ', ': ' );
    foreach my $key ( keys $fstab->%* ) {

        my $fsflags = $fstab->{$key}->{fs_flags};

        if ( kexists( $fstab, $key, 'subvol' ) ) {
            my $subvol = $fstab->{$key}->{subvol};
            $fsflags =~ s/subvol=([^,\s]+)/subvol=$subvol/x;
        }

        # now remove the device= from the fsflags, and insert what is needed
        $fsflags =~ s/device=[^,]+,//xg;
        if ( $raid_level eq 'raidS' ) {
            $fsflags = join( ',', "device=$disk1", $fsflags );
        }
        else {
            $fsflags = join( ',', "device=$disk1", "device=$disk2", $fsflags );
        }

        push(
            $ff->@*,
            join( '',
                $fstab->{$key}->{device}, "\t", $key,                   "\t", $fstab->{$key}->{fs},   "\t",
                $fsflags,                 "\t", $fstab->{$key}->{dump}, "\t", $fstab->{$key}->{pass}, "\n" )
        );
    }
    say 'OK';
    print_table( 'Writing fstab to disk:', $fstab_f, ': ' );
    write_file(
        {
            PATH    => $fstab_f,
            CONTENT => $ff,
        }
    );

    say 'OK';
    return;

}

sub read_fstab ($fstab_f) {

    print_table( 'Reading fstab ', $fstab_f, ': ' );
    my $fstab_struct = parse_file( $fstab_f, \&_struct_fstab, sub { } );

    #print Dumper $fstab_struct;
    die 'ERROR: Parser Error' if ( !$fstab_struct->{'/'}->{device} );

    say 'OK';
    return ($fstab_struct);

}

1;
