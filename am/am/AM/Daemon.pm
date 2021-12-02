package AM::Daemon;

use ModernStyle;
use Exporter qw(import);
use POSIX qw(setsid);                # Daemon and Signals
use English qw( -no_match_vars );    # required for $GID,$EGID,$EUID,$UID

our @EXPORT_OK = qw(am_daemon);

#########################

sub _exit {
    say time(), ": received sigint/term, exiting.";
    exit 0;
}

################################################################

sub am_daemon(@args) {

    my $log      = $args[0] ? shift @args : '/dev/null';
    my $drop_uid = $args[0] ? shift @args : 0;
    my $drop_gid = $args[0] ? shift @args : 0;

    say "Becoming a Daemon...";

    local ( $!, $? );
    $SIG{TERM} = \&_exit;
    $SIG{INT}  = \&_exit;

    chdir '/' or die "Can't chdir to /: $!";
    open STDIN,  "< /dev/null" or die "Can't read /dev/null: $!";
    open STDOUT, ">>$log"      or die "Can't write to $log: $!";
    open STDERR, ">>$log"      or die "Can't write to $log: $!";
    defined( my $pid = fork() ) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";

    return $pid if ( !$drop_uid || !$drop_gid );

    # drop privs
    ($GID) = $drop_gid;
    $EGID = $drop_gid;
    $EUID = $UID = $drop_uid;

    return $pid;
}

#######################

