package Plugins::Container::Cmds::Backup;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use InVivo qw(kexists);
use IO::Config::Check qw(file_exists);
use Tree::Slice qw(slice_tree);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd run_system);
use PSI::System::BTRFS qw(create_btrfs_snapshot_simple delete_btrfs_subvolume_simple);
use PSI::Tag qw(get_tag);

our @EXPORT_OK = qw(import_backup);

## on devop do the following to generate a ssh keypair
## ID is the node identifier, but with a dot instead of a slash.
## so if you setup a node identified by 'staging/stagecontrol', use 'staging.stagecontrol'
#export ID="<ID>"
## the sftp password from hetzner
#export TARGET_PASSWORD="<PASSWORD>"
#cd /data/local_config/secrets
#echo $TARGET_PASSWORD > backup.$ID.sftp.password
## notice, that hetzner is particularly picky about supported ssh keys. thus rsa and rfc4716
## https://wiki.hetzner.de/index.php/Backup_Space_SSH_Keys
#ssh-keygen -t rsa -f backup.$ID.ssh.priv -C "$ID"
## dont use a passphrase
#ssh-keygen -e -f backup.$ID.ssh.priv.pub | grep -v "Comment:" > backup.$ID.ssh.pub
#rm backup.$ID.ssh.priv.pub
## now run the borg backup script in tools
## after that, add the configuration details to the machine configuration

# important Note:
# if there is an existing backup folder offsite, delete it before you update the machine

########################################################################################
sub _do_container_backup ( $container, $maillog ) {

    my $cond_script = sub($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && kexists( $branch->[0], 'backup', 'backup.sh' ) );
        return;
    };

    my $cond_folders = sub($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{FOLDERS} ) );
        return;
    };

    foreach my $entry ( slice_tree( $container, $cond_script ) ) {

        my $name    = $entry->[1]->[0];
        my $tag     = $entry->[1]->[1];
        my $nametag = join( '_', $name, $tag );
        print_table( "Container $nametag", 'backup', ': ' );
        run_cmd("echo Container $nametag backup start >> $maillog");
        run_cmd("docker exec -i $nametag /data/config/backup/backup.sh >> $maillog 2>&1");    # don't use hardcoded path
        run_cmd("echo Container $nametag backup end >> $maillog");
        say 'OK';
    }

    my @folders = ();
    foreach my $e ( slice_tree( $container, $cond_folders ) ) {
        push @folders, $e->[0]->{FOLDERS}->@*;
    }

    return @folders;
}

sub _backup ( $query, @ ) {

    my $borg_base_dir = $query->('backup_path');
    my $data_path     = $query->('data_path');
    my $self          = $query->('self');
    my $group         = $query->('group');
    my $mail          = $query->('mail');
    my $container     = $query->('container');
    my $backup_target = $query->('backup_target');
    my $backup_user   = $query->('backup_user');

    # this and all the other paths (used by the config installer script) should be defined in the config
    my $ssh_priv_key  = '/root/.ssh/backup';
    my $borg_key_file = '/root/.backup_borg_key';
    my $maillog       = '/tmp/bkplog';
    my $backup_path   = '/backup';
    my $remote        = join( '', 'sftp://', $backup_user, '@', $backup_target, $backup_path, '/' );
    my $id            = join( '.', $group, $self );

    print_table( 'Backup', ' ', ": ->\n" );

    die 'ERROR: keys missing' if ( !file_exists $ssh_priv_key || !file_exists $borg_key_file );
    my @includes = _do_container_backup( $container, $maillog );    # run all the container specific backup scripts

    for my $e (@includes) {
        $e = join( '', $backup_path, $e );                          # pad paths
    }

    my $include_string = join( ' ', @includes );
    create_btrfs_snapshot_simple( $data_path, $backup_path );
    print_table( 'Running Offsite Backup', ' ', ': ' );

    my $tag                 = get_tag;
    my $borg_key_env        = "export BORG_KEY_FILE=$borg_key_file; export BORG_BASE_DIR=$borg_base_dir";
    my $borg_create_options = '--verbose --stats --show-rc --compression lz4 --exclude-caches';
    my $backup_command      = "$borg_key_env; borg create $borg_create_options $borg_base_dir/backup::$tag $include_string";
    my $remove_command      = "$borg_key_env; borg prune --list --prefix '{hostname}-' --show-rc --keep-daily 7 --keep-weekly 3 $borg_base_dir/backup";
    my $compact_command     = "$borg_key_env; borg compact --cleanup-commits $borg_base_dir/backup";
    my $keyscan             = "ssh-keyscan $backup_target 2>&1 | grep -v '^#'";
    my $ec_handler          = sub($p) {
        say Dumper $p;
        return;
    };

    run_system $ec_handler,
      "mkdir -p $borg_base_dir/backup >> $maillog",
      "echo keyscan >> $maillog",
"for i in \$($keyscan | sed -e 's/.*[ ]//'); do grep -q \$i /root/.ssh/known_hosts; if [ \$? == 1 ]; then $keyscan | grep \$i >> /root/.ssh/known_hosts; fi done",
      "echo mount backup >> $maillog",
      "sshfs -oIdentityFile=$ssh_priv_key $backup_user\@$backup_target:backup $borg_base_dir/backup >> $maillog 2>&1",    # mount target
      "echo borg backup >> $maillog",
      "$backup_command >> $maillog 2>&1",
      "echo borg prune >> $maillog",
      "$remove_command >> $maillog 2>&1",
      "echo borg compact >> $maillog",
      "$compact_command >> $maillog 2>&1",
      "fusermount3 -u $borg_base_dir/backup >> $maillog 2>&1",
      "cat $maillog | mail -s 'Backup $group/$self' $mail",
      "rm -f $maillog";
    say 'OK';

    delete_btrfs_subvolume_simple("$backup_path$data_path");
    return;
}

sub import_backup ($enable) {

    my $struct = {
        backup => {

            # don't change the name, it is also stored in the HostOS backup key creation command, for the cronjob
            now => {
                CMD  => \&_backup,
                DESC => 'run backup task',
                HELP => ['run backup task'],
                DATA => {
                    data_path   => 'paths data ROOT',
                    backup_path => 'paths data BACKUP',
                    self        => 'machine self NAMES SHORT',
                    group       => 'machine self GROUP',

                    # backup service relies on ssmtp to be working.
                    mail          => 'machine self COMPONENTS SERVICE ssmtp MAILLOG',
                    backup_target => 'machine self COMPONENTS SERVICE backup TARGET',
                    backup_user   => 'machine self COMPONENTS SERVICE backup TARGET_USER',
                    container     => 'container',
                }
            }
        }
    };

    $struct->{backup}->{now}->{ENABLE} = 'no' unless ($enable);

    return $struct;
}
1;
