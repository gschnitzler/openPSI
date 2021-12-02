package Plugins::Deploy::Libs::Container;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);

our @EXPORT_OK = qw(get_container);

############

sub get_container ( $config, $container ) {

    return ( '', '' ) unless ($container);

    my ( $arg_name, $arg_tag ) = split /_/, $container;
    if ( !$arg_name || !$arg_tag || !kexists( $config, $arg_name, $arg_tag ) ) {
        say "ERROR: container $container not found";
        return;
    }

    return ( $arg_name, $arg_tag );
}
