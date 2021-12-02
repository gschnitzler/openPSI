package Plugins::Container::Cmds::State;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_line);

our @EXPORT_OK = qw(import_state);

sub _state ( $query, @args ) {

    my $docker_container = $query->('docker_container');

    print_line('Container System State');

    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;

    if ( scalar keys $docker_container->%* == 0 ) {
        say 'No containers running';
    }
    else {
        say Dumper $docker_container;
    }

    print_line('');    # '' needed for perl signatures
    say '';

    return;
}

###############################################
# Frontend Functions

sub import_state () {

    my $struct = {
        container => {
            state => {
                CMD  => \&_state,
                DESC => 'prints Container state information',
                HELP => ['prints Container state information'],
                DATA => { docker_container => 'state docker_container', }
            }
        }
    };

    return $struct;
}
1;

