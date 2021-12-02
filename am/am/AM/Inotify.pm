package AM::Inotify;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Path qw(make_path);
use Linux::Inotify2;
use Readonly;

use IO::Config::Check qw(file_exists dir_exists);
use PSI::Parse::Dir qw(get_directory_list);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(am_inotify);

##################################################
# Linux::Inotify2 exports all events as barewords, which translate back to their respective bitmask.
# meaning you can not use variables containing the event names when creating a watch(), but have to use the barewords.
# here is a lookup table (event => mask):
my $inotify_event_lt = {
    IN_ACCESS        => 1,       # say "IN_ACCESS: ",           IN_ACCESS;
    IN_MODIFY        => 2,       # say "IN_MODIFY: ",           IN_MODIFY;
    IN_ATTRIB        => 4,       # say "IN_ATTRIB: ",           IN_ATTRIB;
    IN_CLOSE_WRITE   => 8,       # say "IN_CLOSE_WRITE: ",      IN_CLOSE_WRITE;
    IN_CLOSE_NOWRITE => 16,      # say "IN_CLOSE_NOWRITE: ",    IN_CLOSE_NOWRITE;
    IN_CLOSE         => 24,      # say "IN_CLOSE: ",            IN_CLOSE;
    IN_OPEN          => 32,      # say "IN_OPEN: ",             IN_OPEN;
    IN_MOVED_FROM    => 64,      # say "IN_MOVED_FROM: ",       IN_MOVED_FROM;
    IN_MOVED_TO      => 128,     # say "IN_MOVED_TO: ",         IN_MOVED_TO;
    IN_MOVE          => 192,     # say "IN_MOVE: ",             IN_MOVE;
    IN_CREATE        => 256,     # say "IN_CREATE: ",           IN_CREATE;
    IN_DELETE        => 512,     # say "IN_DELETE: ",           IN_DELETE;
    IN_DELETE_SELF   => 1024,    # say "IN_DELETE_SELF: ",      IN_DELETE_SELF;
    IN_MOVE_SELF     => 2048,    # say "IN_MOVE_SELF: ",        IN_MOVE_SELF;
    IN_ALL_EVENTS    => 4095,    # say "IN_ALL_EVENTS: ",       IN_ALL_EVENTS;
};

# in addition to events understood by watchers, there are others that we want to trip over
my $inotify_error_lt = {
    IN_UNMOUNT     => 8192,          # say "IN_UNMOUNT: ",     IN_UNMOUNT;
    IN_Q_OVERFLOW  => 16384,         # say "IN_Q_OVERFLOW: ",  IN_Q_OVERFLOW;
    IN_IGNORED     => 32768,         # say "IN_IGNORED: ",     IN_IGNORED;
    IN_ONLYDIR     => 16777216,      # say "IN_ONLYDIR: ",     IN_ONLYDIR;
    IN_DONT_FOLLOW => 33554432,      # say "IN_DONT_FOLLOW: ", IN_DONT_FOLLOW;
    IN_MASK_ADD    => 536870912,     # say "IN_MASK_ADD: ",    IN_MASK_ADD;
    IN_ISDIR       => 1073741824,    # say "IN_ISDIR: ",       IN_ISDIR;
    IN_ONESHOT     => 2147483648,    # say "IN_ONESHOT: ",     IN_ONESHOT;
};
my $inotify_event_lt_reverse = { reverse $inotify_event_lt->%* };    # for reverse lookups (mask => event), this table is used
my $inotify_error_lt_reverse = { reverse $inotify_error_lt->%* };    # for reverse lookups (mask => event), this table is used
my $check_path               = {
    is_absolute => sub ($path) {
        return 0 if !$path || $path !~ /^\//;
        return 1;
    },
    make_dir => sub ($path) {
        local ( $!, $? );
        return 1 if dir_exists $path;
        print '(creating path) ';
        unless ( make_path $path) {
            say 'failed';
            return 0;
        }
        return 1;
    },
    handler => sub ($handler) {
        return 1 if $handler && ref $handler eq 'CODE';
        return 0;
    }
};

################################################################################

sub _get_files_from_dir($path) {

    my $dir_content = get_directory_list($path);
    my @files       = ();

    for my $e ( sort keys $dir_content->%* ) {
        push @files, $e if ( !ref $dir_content->{$e} && $dir_content->{$e} eq 'f' );
    }
    return @files;
}

sub _get_stale_files ( $path, $event, $handler ) {

    my @files = ();
    for my $file ( _get_files_from_dir $path ) {
        push @files, [ $handler, $path, $event, $file ] if file_exists join( '/', $path, $file );
    }

    my @sorted = sort { $a->[3] cmp $b->[3] } @files;    # sort by file name. as this is called per event, no further sorting required.
    return @sorted; # 'return sort ...' is undefined behavior if called in scalar context
}

sub _init_watchers ( $inotify, $watchers, $cf ) {

    my @stale_files   = ();
    my $process_stale = ( exists $cf->{process_stale} && $cf->{process_stale} == 1 ) ? 1 : 0;

    for my $path ( sort keys $watchers->%* ) {
        for my $event ( sort keys $watchers->{$path}->%* ) {

            my $handler = $watchers->{$path}->{$event};
            print_table "Starting $path", $event, ': ';
            push @stale_files, _get_stale_files( $path, $event, $handler ) if $process_stale;
            die "ERROR: event $event does not exist in lookup table" unless exists( $inotify_event_lt->{$event} );
            $inotify->watch( $path, $inotify_event_lt->{$event}, $handler ) or die "ERROR: could not create inotify event $event for $path: $!";
            say 'OK';
        }
    }
    return @stale_files;
}

sub _prepare_handler ( $path, $config ) {

    my $handler = $config->{handler};
    my $args    = $config->{args};

    die "ERROR: invalid path '$path': not an absolute path"               unless $check_path->{is_absolute}->($path);
    die "ERROR: could not create '$path': not a read/writeable directory" unless $check_path->{make_dir}->($path);
    die "ERROR: no or invalid handler for $path"                          unless $check_path->{handler}->($handler);

    return sub ( $e, @stale_args ) {

        # in case the handler is not called from inotify, but directly on stale files
        return $handler->( $stale_args[0], $stale_args[1], $args ) if ( $#stale_args == 1 );

        my $filepath = $e->fullname;
        my $mask     = $e->mask;

        if ( exists $inotify_event_lt_reverse->{$mask} ) {
            my $event = $inotify_event_lt_reverse->{$mask};
            return $handler->( $filepath, $event, $args );
        }

        if ( exists $inotify_error_lt_reverse->{$mask} ) {
            my $event = $inotify_error_lt_reverse->{$mask};
            die "ERROR: event '$event' forced watcher to unregister ($filepath)";
        }

        die "ERROR: $mask";
    };
}

sub _prepare_handlers ( $paths ) {

    my $watchers = {};

    for my $path ( sort keys $paths->%* ) {
        for my $event ( sort keys $paths->{$path}->%* ) {
            print_table "Setup $path", $event, ': ';
            $watchers->{$path}->{$event} = _prepare_handler( $path, $paths->{$path}->{$event} );
            say 'OK';
        }
    }
    return $watchers;
}

#########################

sub am_inotify($config) {

    my $global_config = $config->{global};
    my $inotify       = Linux::Inotify2->new or die "unable to create new inotify object: $!";

    # start watchers and reinject stale files, if any/wanted
    for my $e ( _init_watchers( $inotify, _prepare_handlers( $config->{paths} ), $global_config ) ) {
        my ( $handler, $path, $event, $file ) = $e->@*;
        $handler->( {}, "$path/$file", $event );    # stale files
    }

    # while poll executes its callback handler, it blocks until the handler returns.
    # so callback handlers in watch() can not be used to actually process files (with external/long-lived programs), as it does not scale.
    # there is a streaming interface, using read(), that returns all unprocessed events. read() can be used in a blocking and nonblocking fashion.
    # there are a few scenarios for both interfaces.
    # in all variants, the watch() handler should return as soon as possible and block.
    # as forking here is still expensive, i decided to just implement a wrapper calling small/fast handler programs.
    # as such, poll() seemed the better choice.
    # the handlers should best be used to just offload the events to other programs via a fast msg mechanism
    $inotify->poll while 1;
    return;
}

