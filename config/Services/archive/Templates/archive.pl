#!/usr/bin/perl

use 5.014;
use strict;
use warnings;
use feature ( ":5.24", "signatures" );
no warnings "experimental::signatures";
use POSIX qw(setsid);    # Daemon and Signals

#use English qw( -no_match_vars );    # required for $GID,$EGID,$EUID,$UID
use Linux::Inotify2;
use Net::SFTP;

#####################

my $knownhosts_file = '/var/lib/archive_known_hosts';
my $search_path     = '/data/container';                                            # there is no genesis variable for that path
my $sftp_host       = '[% machine.self.COMPONENTS.SERVICE.archive.HOST %]';
my $sftp_user       = '[% machine.self.COMPONENTS.SERVICE.archive.USER %]';
my $sftp_identity   = '[% machine.self.COMPONENTS.SERVICE.archive.KEYFILE %]';
my $sftp_port       = '[% machine.self.COMPONENTS.SERVICE.archive.PORT %]';
my $sftp_pub        = '[% machine.self.COMPONENTS.SERVICE.archive.REMOTE_PUB %]';

#####################

sub _transfer_file($file_path) {
    say "New file moved in: $file_path";

    # ignore non archives
    return unless ( $file_path =~ /\.tar\.bz2$/ );

    my @folders   = split( '/', $file_path );
    my $file_name = pop @folders;
    my $archive   = pop @folders;
    if ( $archive ne 'archive' ) {
        say "ERROR: nested entry '$archive'";
        return;
    }
    my $type      = pop @folders;
    my $container = pop @folders;

    system(
        "sftp -oUserKnownHostsFile=$knownhosts_file -P $sftp_port -i $sftp_identity $sftp_user\@$sftp_host << EOF\ncd /$container/$type/\nput $file_path\nquit\nEOF\n\n"
    );

    # delete file
    unlink $file_path;

    return;
}

sub archive_server($path) {

    open( my $fh, '-|', "find $path -type d | grep 'archive\$'" );
    my @watch_dirs = <$fh>;
    close($fh);

    # setup a knownhosts file used for sftp
    $sftp_pub =~ s/\ [^ ]+$//;
    open( my $fha, '>', $knownhosts_file );
    say $fha "[$sftp_host]:$sftp_port $sftp_pub";
    close($fh);
    system("chmod 500 $knownhosts_file");

    die 'ERROR: nothing to watch' if ( scalar @watch_dirs == 0 );
    my $inotify = new Linux::Inotify2 or die "unable to create new inotify object: $!";

    my $handler = sub ($event) {
        return _transfer_file( $event->fullname );
    };

    foreach my $dir (@watch_dirs) {
        chomp $dir;
        die "ERROR: invalid path '$dir', not a read/writeable directory" if ( !-e $dir || !-r $dir || !-w $dir || !-d $dir );
        $inotify->watch( $dir, IN_MOVED_TO, $handler );

        # move off files that are left over from before
        opendir( my $dh, $dir ) || die "ERROR: cannot opendir $dir: $!";
        my @files = readdir($dh);
        closedir $dh or die 'ERROR: closing';

        foreach my $file (@files) {
            _transfer_file( join( '/', $dir, $file ) ) if ( -f $file );
        }
    }

    1 while $inotify->poll;
    return;
}

#####################
sub _exit {
    say time(), ": received sigint/term, exiting.";
    exit 0;
}

sub daemonize {

    my ($stdout_log) = @_;
    say "Becoming a Daemon...";

    chdir '/' or die "Can't chdir to /: $!";
    open STDIN,  "< /dev/null"   or die "Can't read /dev/null: $!";
    open STDOUT, ">>$stdout_log" or die "Can't write to $stdout_log: $!";
    open STDERR, ">>$stdout_log" or die "Can't write to $stdout_log: $!";
    defined( my $pid = fork() ) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";

    # drop privs to etl user and group
    #($GID) = 10601;
    #$EGID = 10601;
    #$EUID = $UID = 10601;

    return $pid;
}

#######################

$SIG{TERM} = \&_exit;
$SIG{INT}  = \&_exit;

daemonize('/dev/null');
archive_server($search_path);
exit $?;

