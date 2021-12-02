package Plugins::Build::Filter::Services;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_services);

#########

sub add_services ( $machine, $services ) {

    my $machine_name     = $machine->{NAMES}->{SHORT};
    my $cluster_name     = $machine->{GROUP};
    my $machine_services = $machine->{COMPONENTS}->{SERVICE};

    print_table( 'Add Services', "$cluster_name/$machine_name", ': ' );

    my $machine_service_templates = {};
    foreach my $required_service ( sort keys( $machine_services->%* ) ) {

        next unless ( $machine_services->{$required_service}->{ENABLE} eq 'yes' );
        print "$required_service ";
        die "ERROR: Service $required_service not found " unless exists( $services->{$required_service} );
        $machine_service_templates->{$required_service} = $services->{$required_service};
    }
    say '';
    return $machine_service_templates;
}
