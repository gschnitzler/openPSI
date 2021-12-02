package Plugins::Cloudflare::Lib::Print;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table pad_string);

our @EXPORT_OK = qw(print_dns);

my @supported_type = ( 'A', 'TXT' );
my $length = 0;

foreach my $e (@supported_type) {
    my $l = length $e;
    $length = $l if $length < $l;
}

##########

sub print_dns($t) {

    foreach my $zone_name ( sort keys $t->%* ) {

        foreach my $type_name (@supported_type) {

            my $padded_type_name = pad_string( $type_name, $length );

            foreach my $a_name ( sort keys $t->{$zone_name}->{$type_name}->%* ) {

                my ( $proxied, @content );

                foreach my $c_name ( sort keys $t->{$zone_name}->{$type_name}->{$a_name}->%* ) {

                    my $e = $t->{$zone_name}->{$type_name}->{$a_name}->{$c_name};

                    #$type    = $e->{type};
                    $proxied = $e->{proxied};
                    push @content, $e->{content};

                }
                if ( $type_name eq 'TXT' ) {

                    # TXT records are long and might even container ','.
                    # also, they are normaly standalone.
                    # so use a line per entry
                    print_table "$padded_type_name $proxied $zone_name", $a_name, join( '', ': [ ', $_, " ]\n" ) for (@content);

                }
                else {
                    print_table "$padded_type_name $proxied $zone_name", $a_name, join( '', ': [ ', join( ',', @content ), " ]\n" );
                }

            }
        }
    }
    return;
}

1;
