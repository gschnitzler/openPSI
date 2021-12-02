package Plugins::Config::Secrets::Cmds::Manage;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use MIME::Base64;
use Digest::MD5 qw(md5_base64);

use PSI::Console qw(print_table read_stdin);
use PSI::Parse::Dir qw(get_directory_list);
use PSI::Parse::File qw(read_files write_files);
use PSI::RunCmds qw(run_open);

our @EXPORT_OK = qw(import_manage);

my $store_name = 'psi-secrets';

sub _read_from_pass(@a) {

    my @content = run_open join( ' ', '/usr/bin/pass', @a );
    s/\x1b\[[0-9;]*m//g for @content;    # remove nasty colour codes from tree
    return @content;
}

sub _get_pass_list() {

    my $pass_list = {};

    foreach my $secret_name ( _read_from_pass($store_name) ) {

        next unless $secret_name =~ s/^.*──\s+//;
        $pass_list->{$secret_name} = '';
    }
    return $pass_list;
}

sub _get_local_secrets ($path) {

    my $list = get_directory_list($path);
    delete $list->{'.cfmeta'} if exists( $list->{'.cfmeta'} );    # ignore the meta file
    $list->{$_} = '' for keys $list->%*;                          # change the format
    return $list;
}

sub _find_and_remove_missing ( $l, $r ) {

    my $missing = {};
    foreach my $k ( keys $l->%* ) {
        next if exists $r->{$k};
        $missing->{$k} = delete $l->{$k};
    }
    return $missing;
}

sub _print_changes ( $h, $msg ) {

    my $hit = 0;
    for my $k ( sort keys $h->%* ) {
        print_table $msg, ' ', ": $k\n";
        $hit = 1;
    }
    _yes_or_no() if $hit;
    return $hit;
}

sub _delete_from_store($delete) {

    return unless _print_changes( $delete, 'REMOVE FROM STORE' );
    foreach my $secret_name ( keys $delete->%* ) {
        my @answer = _read_from_pass( 'rm', '-f', "$store_name/$secret_name" );
    }
    return;
}

sub _add_to_store ( $add, $spath ) {

    return unless _print_changes( $add, 'ADD TO STORE' );
    foreach my $secret_name ( keys $add->%* ) {
        say $secret_name;
        my @answer = _read_from_pass("insert -f -m $store_name/$secret_name < $spath/$secret_name");
    }
    return;
}

sub _update_store ( $update, $spath ) {

    return unless _print_changes( $update, 'UPDATE IN STORE' );
    foreach my $secret_name ( keys $update->%* ) {
        my @answer = _read_from_pass("insert -f -m $store_name/$secret_name < $spath/$secret_name");
    }
    return;
}

sub _yes_or_no() {
    while ( my $line = read_stdin( 'Are you sure you want to apply these changes? [yes|no] ', -style => 'bold red' ) ) {
        last   if $line eq 'yes';
        exit 0 if ( $line eq 'no' );
    }
    return;
}

sub _decrypt_store_secrets($list) {

    for my $secret_name ( sort keys $list->%* ) {
        print_table 'Decrypting', $secret_name, ': ';
        $list->{$secret_name} = join( "\n", _read_from_pass("$store_name/$secret_name"), '' );    # '' adds a newline after last line
        say 'OK';
    }
    return;
}

sub _find_changed_secrets ( $store_secret_list, $local_secrets_path ) {

    my $update_store = {};

    for my $secret_name ( keys $store_secret_list->%* ) {

        my ( $file_content_base64, $file_content ) = ( '', '' );
        my $local_file = read_files("$local_secrets_path/$secret_name");

        if ( exists( $local_file->{BASE64} ) && $local_file->{BASE64} ) {

            shift $local_file->{CONTENT}->@*;    # remove the binary warning header
            $file_content_base64 = join( "\n", $local_file->{CONTENT}->@*, '' );                 # '' adds a newline after last line
            $file_content        = decode_base64( join( "\n", $local_file->{CONTENT}->@* ) );    # lets hope that binaries don't end with a newline
            chop $store_secret_list->{$secret_name};                                             # ... and remove the added newline read from pass
        }
        else {
            $file_content_base64 = encode_base64( join( "\n", $local_file->{CONTENT}->@*, '' ) );    # '' adds a newline after last line
            $file_content        = join( "\n", $local_file->{CONTENT}->@*, '' );                     # '' adds a newline after last line
        }

        my $file_md5  = md5_base64($file_content_base64);
        my $store_md5 = md5_base64( encode_base64( $store_secret_list->{$secret_name} ) );

        if ( $file_md5 ne $store_md5 ) {
            $update_store->{$secret_name} = $file_content;
        }
    }
    return $update_store;
}

####################################################################################################

sub _update_git_secrets ( $query, @args ) {

    say 'gpg and thus pass only work in tmux, for some tty reason, where the password screen woud not open otherwise';
    my $local_secrets_path = $query->('CONFIG_PATH');
    my $store_secret_list  = _get_pass_list();
    my $local_secret_list  = _get_local_secrets($local_secrets_path);

    # find secrets that were removed
    my $remove_from_store = _find_and_remove_missing( $store_secret_list, $local_secret_list );

    # find secrets not yet in store
    my $add_to_store = _find_and_remove_missing( $local_secret_list, $store_secret_list );

    # decrypt (remaining) secrets in store.
    # use store_secret_list, as its now the only complete list (but lacking added files, no need to compare those)
    _decrypt_store_secrets($store_secret_list);

    # md5 compare local and store secrets (using store_secret_list)
    my $update_store = _find_changed_secrets( $store_secret_list, $local_secrets_path );

    # remove, add and update store secrets
    _delete_from_store($remove_from_store);
    _add_to_store( $add_to_store, $local_secrets_path );
    _update_store( $update_store, $local_secrets_path );
    return;
}

sub _init_local_secrets ( $query, @args ) {

    my $local_secrets_path = $query->('CONFIG_PATH');
    my $local_secret_list  = _get_local_secrets($local_secrets_path);

    die 'ERROR: local store is not empty!' unless ( keys $local_secret_list->%* == 0 );

    my $store_secret_list = _get_pass_list();
    my @files             = ();

    # decrypt all secrets in store
    _decrypt_store_secrets($store_secret_list);

    # create a file list for write_files
    for my $secret_name ( sort keys $store_secret_list->%* ) {

        push @files, {
            LOCATION => $secret_name,
            CHMOD    => '400',
            CONTENT  => [ '# binary warning', split( /\n/, encode_base64( $store_secret_list->{$secret_name} ) ) ],
            BASE64 => 1,    # as we don't know, lets always assume binary secrets
        };
    }

    write_files( "$local_secrets_path/", \@files, [], 1 );    # write to disk
    return;
}

###########################################
# frontend
#
sub import_manage () {

    my $struct->{init}->{local}->{secrets} = {

        CMD  => \&_init_local_secrets,
        DESC => 'decrypts all store secrets to local folder',
        HELP => ['decrypts all store secrets to local folder'],
        DATA => { CONFIG_PATH => 'CONFIG_PATH' }
    };

    $struct->{update}->{git}->{secrets} = {

        CMD  => \&_update_git_secrets,
        DESC => 'updates store with local secrets',
        HELP => [
            'adds all local secrets to the store that are not there yet.',
            'compares secrets in both locations for changes.',
            'commits changed secrets to store.',
            'WARNING: PREMISE IS THAT THE LOCAL SECRETS ARE ALWAYS MORE UP TO DATE THAN THE ONES IN STORE'
        ],
        DATA => { CONFIG_PATH => 'CONFIG_PATH' }
    };

    return $struct;
}
1;
