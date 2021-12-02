package Plugins::Container::System::GetContainer;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use Tree::Iterators qw(array_iterator);
use PSI::RunCmds qw(run_open);

Readonly my $CONTAINER_ID => 0;
Readonly my $IMAGE        => 1;
Readonly my $COMMAND      => 2;
Readonly my $CREATED      => 3;
Readonly my $STATUS       => 4;
Readonly my $PORTS        => 5;
Readonly my $NAMES        => 6;

# Export
our @EXPORT_OK = qw(get_docker_container);

sub get_docker_container () {

    my $list   = {};
    my @docker = run_open 'docker ps -a --no-trunc 2>&1';
    my @names  = split( /\s{2,}/x, shift @docker );

    # parsing hack: some fields are not always filled.
    # at the time of writing, fields were
    # CONTAINER ID, IMAGE, COMMAND, CREATED, STATUS, PORTS, NAMES
    # it must be trusted that CONTAINER ID, IMAGE and NAMES are are always available, as we need them
    @names = ( $names[$CONTAINER_ID], $names[$IMAGE], $names[$NAMES] );

    #my $names_field = pop @names;
    #pop @names; # remove ports
    #push @names, $names_field;

    while ( my $line = shift @docker ) {

        my @line_elm = split( /\s{2,}/x, $line );

        @line_elm = ( $line_elm[0], $line_elm[1], pop @line_elm );
        die 'ERROR: line has not same elements as header' unless ( @names == @line_elm );

        # match header elements with line elements and create a hash
        my $h  = {};
        my $it = array_iterator( \@names, \@line_elm );
        while ( my ( $n_elm, $l_elm ) = $it->() ) {

            # next unless ($n_elm && $l_elm);
            $h->{$n_elm} = $l_elm;
        }

        my ( $pid, @rest ) = run_open "docker inspect -f '{{.State.Pid}}' $h->{'CONTAINER ID'} 2>&1";
        $h->{PID} = $pid;

        #push @list, $h;
        $list->{ $h->{'CONTAINER ID'} } = $h;
    }

    #    say Dumper \@list;

    return $list;
}

1;
