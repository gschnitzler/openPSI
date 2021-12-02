package AM::Queue;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists kdelete);

our @EXPORT_OK = qw(am_queue);

########################################
# package global queue
my $queue         = {};    # the queue
my $running       = {};    # running tasks
my $wait_on_child = 5;
########################################

sub _drop_from_queue ( $q, $file ) {
    die 'ERROR: unimplemented';
}

sub _start ( $task, $path, $file, @a ) {

    push $queue->{$path}->@*, [ $file, $task ];    # add incoming new tasks to queue. use array to honor incoming order
    $running->{$path} = {} unless exists $running->{$path};    # add location to running
    return "$path/$file", $a[0], 'queued';
}

sub _is_complete($proc) {

    return 0 unless ( $proc->is_complete );
    $proc->wait;
    return 1;
}

sub _wait_before_kill($proc) {

    my $counter = 0;
    while ( !_is_complete($proc) ) {
        sleep 1;    # this blocks, but gives the system time to catch up.
        $counter++;
        last if $counter == $wait_on_child;
    }

    return if $counter == 0;
    return " (waited $counter)" unless $counter == $wait_on_child;
    $proc->kill(9);
    $proc->wait;
    return ' (killed)';
}

sub _finished ( $task, $path, $file, @a ) {

    # always remove a task from any queue.
    # no point in starting a task, when its finish condition was already met.
    # when there is no such task, just ignore it.
    # (ie, the files was deleted or moved.)
    my @output = ();

    if ( kexists( $running, $path, $file ) ) {

        # this is sugar coated fork boilerplate. essentially kill the child if it not exited yet,
        # then read (wait) its exit code so it does not go defunct.
        #my $wait          = _wait_before_kill( $running->{$path}->{$file}->{proc} );
        # but... we do not care about the exit code of our childs, do we?
        # the EC of the handler was emitted via socket, otherwise we wouldn't have reached this code...
        # for catastrophic events (OOM, die, etc) it might be, but is it worth the wait, kill and sleep?
        # lets find out and let $SIG{CHLD} = IGNORE do all the dorty work.
        my $wait;
        my $status_string = "finished ($a[1])";
        $status_string .= $wait if $wait;
        kdelete( $running, $path, $file );
        push @output, [ "$path/$file", $a[0], $status_string ];
    }
    else {
        _drop_from_queue( $queue->{$path}, $file );
        push @output, [ "$path/$file", $a[1], 'ERROR: should be dropped' ];
    }
    return @output;
}

sub _shift ( $socket_path, $max_running ) {

    my @output = ();

    foreach my $path ( keys $running->%* ) {

        # each path has its own queue and
        # $max_running is applied per queue
        my $running_tasks = scalar keys $running->{$path}->%*;
        my $start_tasks   = $max_running - $running_tasks;
        next if $start_tasks <= 0;

        while ( my $e = shift $queue->{$path}->@* ) {

            my $file = $e->[0];
            my $task = $e->[1];

            $running->{$path}->{$file}->{child} = $task;
            $running->{$path}->{$file}->{proc}  = $running->{$path}->{$file}->{child}->start;
            $start_tasks--;
            last if $start_tasks <= 0;
        }

        #push @output, [ $path, join( '', "R:", scalar keys $running->{$path}->%*, "/$max_running" ), join( '', 'Q:', scalar $queue->{$path}->@* ) ]
        #  if ( scalar keys $running->{$path}->%* or scalar $queue->{$path}->@* );
    }
    return @output;
}

sub am_queue() {
    return {
        START    => \&_start,
        FINISHED => \&_finished,
        SHIFT    => \&_shift,
    };
}
1;
