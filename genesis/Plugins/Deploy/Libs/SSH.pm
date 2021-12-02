package Plugins::Deploy::Libs::SSH;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(read_stdin);
use PSI::RunCmds qw(run_system run_open);

our @EXPORT_OK = qw(scp_deploy scp_pull ssh_cmd);

############

sub _get_string ( $cmd, $portswitch, $node ) {

    my @string      = ();
    my $remote_host = join '', $node->{user}, '@', $node->{address};

    unless ( exists( $node->{keyfile} ) && $node->{keyfile} ) {
        my $pw = read_stdin( 'SSH Password for given group: ', '-echo', '*' );
        push @string, join '', 'sshpass -p \'', $pw, '\'';
    }

    push @string, $cmd;

    if ( exists( $node->{keyfile} ) && $node->{keyfile} ) {
        push @string, join ' ', '-i', $node->{keyfile};
    }
    else {
        push @string, '-oStrictHostKeyChecking=no';    # sshpass can not handle fingerprint checking. the check is worthless in that case anyway.
    }

    push @string, join ' ', $portswitch, $node->{port};

    return join( ' ', @string ), $remote_host;
}

sub _get_scp_string($node) {
    return _get_string( 'scp -r', '-P', $node );
}

sub _get_ssh_string($node) {
    return _get_string( 'ssh', '-p', $node );
}

sub _find_files ( $wanted, @files ) {

    my $remote_files = {};
    my @found        = ();

    foreach my $file (@files) {

        my ( $item, $tag ) = split /___/, $file;
        next unless ( $item && $tag );
        $tag =~ s/[.].+//x;
        push $remote_files->{$item}->@*, $tag;
    }

    foreach my $item ( keys $remote_files->%* ) {

        next unless $item eq $wanted;
        my @sorted = sort $remote_files->{$item}->@*;
        my $latest = pop @sorted;
        push @found, join '___', $item, $latest;

    }

    if ( scalar @found == 0 ) {
        say "ERROR: No files matched '$wanted'";
        say "Available files:\n";
        say $_ for keys $remote_files->%*;
        return;
    }

    if ( scalar @found > 1 ) {
        say "ERROR: Multiple matches for '$wanted'";
        say 'Be more specific.';
        foreach my $t (@found) {
            if ( $t =~ /^(.+)___/x ) {
                say $1;
            }
        }
        return;
    }

    my @sorted = sort @found;    # perl critic does not like return sort @
    return @sorted;
}

############################

sub ssh_cmd ( $node, $cmd ) {

    say "Connecting to $node->{address} at port $node->{port} :";
    my $ssh = join ' ', _get_ssh_string($node);
    run_system "$ssh '$cmd'";    # $ssh returns non zero code, so system is used
    return;
}

sub scp_deploy ($node) {

    say "Deploying to $node->{address} at port $node->{port} :";

    my ( $cmd, $remote_host ) = _get_scp_string($node);
    my @string        = ();
    my $remote_target = join '', $remote_host, ':', $node->{target};
    my $scp           = join ' ', $cmd, $node->{source}, $remote_target;
    run_system $scp;             # run_cmd returns error, so system is used
    return;
}

sub scp_pull ( $node, $path, $wanted ) {

    say "Connecting to $node->{address} at port $node->{port} :";

    # connect to that machine,  list images and tell what was found, then start downloading it
    # sftp might be better than ssh&scp

    my $ssh = join ' ', _get_ssh_string($node);
    my $scp = join ' ', _get_scp_string($node);
    my @found = _find_files( $wanted, run_open "$ssh 'ls $path'" );

    return if ( scalar @found == 0 );

    my $wf = shift @found;
    $scp = join '', $scp, ':', $path, '/', $wf, '\*', ' ', $path, '/';
    run_system $scp;
    return;
}

