package Plugins::Images::Cmds::State;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);

# Export
our @EXPORT_OK = qw(import_state);

sub _print_state ( $query, @ ) {

    print_table( 'Known Images:', ' ', ":\n" );
    say Dumper $query->('images');

    return;
}

###############################################
# Frontend Functions

sub import_state () {

    my $struct = {
        images => {
            state => {
                CMD  => \&_print_state,
                DESC => 'print image state information',
                HELP => ['prints image state information'],
                DATA => {
                    images => 'state images',

                }
            }
        }
    };

    return $struct;
}
1;

