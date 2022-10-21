package Plugins::Cloudflare::Lib::Print;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use API::Cloudflare qw(supported_types_and_length_cloudflare);
use PSI::Console qw(print_table pad_string);

our @EXPORT_OK = qw(print_dns);

my ( $length, @supported_type ) = supported_types_and_length_cloudflare();

#############################################

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

                    if ( exists $e->{priority} ) {
                        push @content, join( ':', $e->{priority}, $e->{content} );
                    }
                    else {
                        push @content, $e->{content};
                    }

                }
                if ( $type_name eq 'A' ) {
                    print_table "$padded_type_name $proxied $zone_name", $a_name, join( '', ': [ ', join( ',', @content ), " ]\n" );
                }
                else {
                    print_table "$padded_type_name $proxied $zone_name", $a_name, join( '', ': [ ', $_, " ]\n" ) for (@content);

                }
            }
        }
    }
    return;
}

1;
