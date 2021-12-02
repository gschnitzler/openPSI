package Config::Forker::Handler;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Copy;

use PSI::RunCmds qw(run_open);
use IO::Config::Check qw(file_exists);
use AM::STDout qw(write_stdout);
use AM::Socket::Client qw(client);

our @EXPORT_OK = qw(default_handler success_handler move_handler launch_handler sftp_client_handler);

#########################

sub _get_external_handler ( $handlers, $file_name ) {
    foreach my $handler ( keys $handlers->%* ) {
        return $handlers->{$handler} if ( $file_name =~ /$handler/ );
    }
    return;
}

#########################

sub default_handler ( $client, $source_path, $source_file, $event, $config_args, @ ) {
    write_stdout $client, "$source_path/$source_file", $event, 'IGNORED';
    return;
}

sub success_handler ( $client, $source_path, $source_file, $event, $config_args, @ ) {
    my $say = $config_args->{say};
    write_stdout $client, "$source_path/$source_file", $event, $say;
    local ( $?, $! );
    unlink "$source_path/$source_file" or return 1;
    return;
}

sub move_handler ( $client, $source_path, $source_file, $event, $config_args, @ ) {

    my $from = join( '/', $source_path, $source_file );
    my $to   = $config_args->{move_to};
    write_stdout $client, $from, $event, 'started';
    move $from, $to or return 1;
    return 0;
}

# handler that starts an external program, redirects its output back to the socket,
# deletes source file on success and returns the exit code
sub launch_handler ( $client, $source_path, $source_file, $event, $config_args, @ ) {

    my $fp_source    = join '/', $source_path, $source_file;
    my $fp_dest      = join '/', $config_args->{out_dir}, $source_file;
    my $handler      = _get_external_handler( $config_args->{handler}, $source_file );
    my $handler_args = "-source_archive $fp_source -target_archive $fp_dest";
    my $error        = 0;

    unless ( $handler and file_exists $handler) {
        write_stdout $client, $fp_source, $event, 'ERROR: no handler found';
        return 1;
    }

    write_stdout $client, $fp_source, $event, 'started';

    my $open_error = sub ( $cmd, $msg, $ec ) {    # permissions, or file got deleted before this handler is run.
        write_stdout $client, $fp_source, $event, $handler, "ERROR: opening MSG:'$msg' EC:'$ec'";
        $error = 1;
        return;
    };
    my $close_error = sub ( $cmd, $msg, $ec ) {    # file got deleted while running?
        write_stdout $client, $fp_source, $event, $handler, "ERROR: closing MSG:'$msg' EC:'$ec'";
        $error = 2;
        return;
    };
    my $read_handler = sub ( $stop, $line ) {
        chomp $line;
        write_stdout $client, $fp_source, $event, $handler, $line;
        return;
    };

    # delete file after successful transmission.
    # this in turn triggers another inotify event.
    # this check is here for when this handler triggers on a subsequent IN_CLOSE_WRITE
    unless ( file_exists $fp_source) {
        write_stdout $client, $fp_source, $event, 'NOOP (deleted)';
        return $error;
    }

    run_open join( ' ', $handler, $handler_args ), $close_error, $open_error, $read_handler;
    unless ($error) {
        local ( $?, $! );
        unlink $fp_source or die "ERROR: could not delete $fp_source";
    }

    return $error;
}

# use sftp to transfer files off
sub sftp_client_handler ( $client, $source_path, $source_file, $event, $config_args, @ ) {

    my $fp_source    = join( '/', $source_path, $source_file );
    my $sftp_servers = $config_args->{servers};
    my $error        = 0;
    my @handlers     = ();

    write_stdout $client, $fp_source, $event, 'started';

    foreach my $host ( sort keys $sftp_servers->%* ) {

        # sftp is used directly, because of various issues with the perl versions.
        # scp is not possible because of lacking shell access on the remote servers
        # all the piping and redirecting makes msg redirecting to parent troublesome.
        # sftp error msgs would be nice for debugging, but otherwise we dont care.
        my $port       = $sftp_servers->{$host}->{port};
        my $user       = $sftp_servers->{$host}->{user};
        my $key        = $sftp_servers->{$host}->{key};
        my $knownhosts = $sftp_servers->{$host}->{known_hosts_file};
        my $dir        = $sftp_servers->{$host}->{root_dir};
        push @handlers,
          [
            "$user\@$host:$port",
            "sftp -oUserKnownHostsFile=$knownhosts -b - -P $port -i $key $user\@$host << EOF 2>&1\ncd $dir\nput $fp_source\nquit\nEOF\n\n"
          ];
    }

  LP: while (1) {
        foreach my $handler (@handlers) {

            my ( $server, $sftp_cmd ) = $handler->@*;

            my $open_error = sub ( $cmd, $msg, $ec ) {    # permissions, or file got deleted before this handler is run.
                write_stdout $client, $fp_source, $event, $server, "ERROR: opening MSG:'$msg' EC:'$ec'";
                $error = 1;
                return;
            };
            my $close_error = sub ( $cmd, $msg, $ec ) { 
                write_stdout $client, $fp_source, $event, $server, "ERROR: closing MSG:'$msg' EC:'$ec'";
                $error = 2;
                return;
            };
            my $read_handler = sub ( $stop, $line ) {

                $line =~ s/\R//g; # sftp uses more than one and other linebreaks than \n
                return if $line =~ /^sftp\s*>\s/;
                #return if $line =~/^\s+$/;
                #return unless $line;
                write_stdout $client, $fp_source, $event, $server, "'$line'";
                return;
            };

            run_open $sftp_cmd, $close_error, $open_error, $read_handler;
            last LP unless $error;
        }

        write_stdout $client, $fp_source, $event, "INFO: No remote servers available, retrying...";

        sleep 10;    # if no handler responds, they wont for some time.
    }

    unless ($error) {
        local ( $?, $! );
        unlink $fp_source or die "ERROR: could not delete $fp_source";
    }

    return $error;
}

1;

