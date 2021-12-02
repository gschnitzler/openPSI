package Plugins::Network::Cmds::State;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);

# Export
our @EXPORT_OK = qw(import_state);

sub _print_state ( $query, @ ) {

    print_table( 'IPs:', ' ', ":\n" );
    say Dumper $query->('network');
    return;
}

###############################################
# Frontend Functions

sub import_state () {

    my $struct = {
        network => {
            state => {
                CMD  => \&_print_state,
                DESC => 'print network state information',
                HELP => ['prints network state information'],
                DATA => {
                    network => 'state network'

                }
            }
        }
    };

    return $struct;
}
1;

