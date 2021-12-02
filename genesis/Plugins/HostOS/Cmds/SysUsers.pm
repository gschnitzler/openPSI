package Plugins::HostOS::Cmds::SysUsers;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);
use File::Path qw(remove_tree make_path);

use InVivo qw(kexists);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd run_system run_open);
use PSI::Parse::File qw(write_file);
use Plugins::HostOS::Libs::Parse::Users qw(write_users);

our @EXPORT_OK = qw(import_sysusers);

#######################################################

sub _gen_pw () {

    my ( $pw,   @a ) = run_open 'cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c${1:-32}';
    my ( $salt, @b ) = run_open 'cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c${1:-8}';
    return crypt( $pw, "\$6\$$salt\$" );
}

sub _clean_host_users($host_users) {

    print_table 'Users: ', '(current)', ': ';
    my $ok = 0;

    # delete all current users. leave a users primary group in the groups file though
    # if it is used again, it is overridden below, otherwise it will stay.
    foreach my $k ( keys $host_users->{shadow}->%* ) {

        next if $k eq 'root';

        if ( $host_users->{shadow}->{$k}->{PW} ne '!' && $host_users->{shadow}->{$k}->{PW} ne '*' ) {

            print "$k ";
            $ok++;

            delete $host_users->{shadow}->{$k};
            delete $host_users->{passwd}->{$k};

            foreach my $entry ( keys $host_users->{group}->%* ) {

                my $r = delete $host_users->{group}->{$entry}->{USERS};

                #                next unless $r;
                my @members     = split( /,/, $r );
                my @new_members = ();
                foreach my $member (@members) {
                    push @new_members, $member unless ( $member eq $k );
                }
                $host_users->{group}->{$entry}->{USERS} = join( ',', @new_members );
            }
        }
    }
    print 'NO' unless ($ok);
    print "\n";
    return;
}

sub _create_users ( $host_users, $type, $accounts ) {

    print_table 'Groups: ', $type, ': ';
    my $ok = 0;

    foreach my $k ( keys $accounts->{GROUPS}->%* ) {

        print "$k ";
        $ok++;

        my $group_gid = $accounts->{GROUPS}->{$k}->{GID};
        $host_users->{group}->{$k} = {
            PW    => 'x',
            GID   => $group_gid,
            USERS => ''
        };
    }
    print 'NO' unless ($ok);
    print "\n";

    $ok = 0;

    print_table 'Users: ', $type, ': ';
    foreach my $k ( keys $accounts->{USERS}->%* ) {

        print "$k ";
        $ok++;

        my $user = $accounts->{USERS}->{$k};
        my $pw   = _gen_pw();

        # just link in config and add the rest, write_users will ignore keys it does not know
        $host_users->{passwd}->{$k}         = dclone($user);
        $host_users->{passwd}->{$k}->{PW}   = 'x';
        $host_users->{passwd}->{$k}->{DESC} = "genesis $type account";
        $host_users->{shadow}->{$k}         = {
            PW          => $pw,
            LASTCHANGED => '1',
            MIN         => '0',
            MAX         => '99999',
            WARN        => '7',
            INACTIVE    => '',
            EXPIRE      => '',
        };

        # mainly used for wheel. users cannot become root without beeing in wheel
        foreach my $g ( split( /,/, $user->{GROUPS} ) ) {

            # special case first invocation
            if ( !$host_users->{group}->{$g}->{USERS} ) {
                $host_users->{group}->{$g}->{USERS} = $k;
                next;
            }

            $host_users->{group}->{$g}->{USERS} = join( ',', $host_users->{group}->{$g}->{USERS}, $k );
        }
    }
    print 'NO' unless ($ok);
    print "\n";
    return;
}

sub _add_accounts ( $type, $accounts, $known_hosts ) {

    print_table 'Adding Accounts: ', $type, ": ->\n";

    foreach my $k ( keys $accounts->{USERS}->%* ) {

        my $user         = $accounts->{USERS}->{$k};
        my $home         = $user->{HOME};
        my $gauth        = join( '/', $home, '.google_authenticator' );
        my $ssh_dir      = join( '/', $home, '.ssh' );
        my $auth_keys    = join( '/', $ssh_dir, 'authorized_keys' );
        my $known_host_p = join( '/', $ssh_dir, 'known_hosts' );
        my $uid          = $user->{UID};
        my $gid          = $user->{GID};

        {
            local ( $?, $! );
            print_table 'Removing home: ', $home, ': ';
            remove_tree( $home, { keep_root => 1 } );
            say 'OK';

            print_table 'Creating home: ', $home, ': ';
            make_path($ssh_dir);
        }

        run_cmd("touch $home/FILES_HERE_ARE_NOT_PRESERVED");
        write_file(
            {
                PATH    => $auth_keys,
                CONTENT => [ $user->{SSH}->{PUB} ],
                CHMOD   => 600
            },
            {
                PATH    => $known_host_p,
                CONTENT => [ join( "\n", $known_hosts->@*, '' ) ],
                CHMOD   => 600
            }
        );
        write_file(
            {
                PATH    => $gauth,
                CONTENT => [ $user->{GAUTH}->{PUB} ],
                CHMOD   => 400
            }
        ) if ( kexists( $user, 'GAUTH', 'PUB' ) );

        run_cmd("chmod 700 $ssh_dir");
        run_cmd("chown -R $uid:$gid $home");
        run_cmd("chmod 750 $home");

        say 'OK';
    }

    return;
}

sub _build_known_hosts ( $nodes, $adjacent ) {

    my $hosts = [];

    foreach my $node_name ( keys $nodes->%* ) {

        my $node          = $nodes->{$node_name};
        my $node_hostname = $node->{NAMES}->{FULL};
        my $node_ip       = $node->{NETWORK}->{PUBLIC}->{ADDRESS};
        my $node_pub      = $node->{COMPONENTS}->{SERVICE}->{ssh}->{HOSTKEYS}->{ED25519}->{PUB};
        my $node_port     = $node->{COMPONENTS}->{SERVICE}->{ssh}->{SSHPORT};

        $node_pub =~ s/[ ][^ ]+$//;
        push $hosts->@*, "[$node_hostname]:$node_port,[$node_ip]:$node_port $node_pub";
    }

    foreach my $oc_name ( keys $adjacent->%* ) {
        foreach my $om_name ( keys $adjacent->{$oc_name}->%* ) {

            my $other_machine = $adjacent->{$oc_name}->{$om_name};

            #say Dumper $other_machine;
            my $om_hostname = $other_machine->{HOSTNAME};
            my $om_ip       = $other_machine->{NETWORK}->{ADDRESS};
            my $om_pub      = $other_machine->{SSH}->{PUB};
            my $om_port     = $other_machine->{SSH}->{SSHPORT};
            $om_pub =~ s/[ ][^ ]+$//;
            my $e = "[$om_hostname]:$om_port $om_pub";
            if ($om_ip) {
                $e = "[$om_hostname]:$om_port,[$om_ip]:$om_port $om_pub";
            }
            push $hosts->@*, $e;
        }
    }

    return $hosts;
}

sub _add_user ( $query, @args ) {

    my $host_users       = $query->('host_users');
    my $user_accounts    = $query->('user_accounts');
    my $machine_accounts = $query->('machine_accounts');
    my $machine_adjacent = $query->('machine_adjacent');
    my $machine_nodes    = $query->('machine_nodes');
    my $known_hosts      = _build_known_hosts( $machine_nodes, $machine_adjacent );
    my $root_known       = '/root/.ssh/known_hosts';                                  # root also needs a copy

    _clean_host_users($host_users);
    _create_users( $host_users, 'User',    $user_accounts );
    _create_users( $host_users, 'Machine', $machine_accounts );
    write_users($host_users);
    _add_accounts( 'Users',   $user_accounts,    $known_hosts );
    _add_accounts( 'Machine', $machine_accounts, $known_hosts );
    run_system "mkdir -p /root/.ssh && touch $root_known";
    write_file(
        {
            PATH    => $root_known,
            CONTENT => [ join( "\n", $known_hosts->@*, '' ) ],
            CHMOD   => 600
        }
    );
    return;
}

###########################################
# frontend

sub import_sysusers () {

    my $struct = {
        add => {
            users => {
                CMD  => \&_add_user,
                DESC => 'syncs hosts users with config',
                HELP => ['syncs hosts users with config'],
                DATA => {
                    host_users       => 'state user',
                    user_accounts    => 'machine self USER_ACCOUNTS',
                    machine_accounts => 'machine self MACHINE_ACCOUNTS',
                    machine_nodes    => 'machine nodes',
                    machine_adjacent => 'machine adjacent'
                }
            }
        }
    };

    return $struct;
}
1;
