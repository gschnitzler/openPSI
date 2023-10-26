package Plugins::Config::Accounts::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Config::Check qw(check_config);
use IO::Config::Read qw(read_config load_config);

our @EXPORT_OK = qw(import_hooks);

my $generic_user = {
    NAME   => [qr/^(.+)/x],
    UID    => [qr/^(\d+)/x],
    GID    => [qr/^(\d+)/x],
    HOME   => [qr/^(\/.*)/x],
    SHELL  => [qr/^(\/.*)/x],
    GROUPS => [qr/^(.*)/x],     # can be empty

};

my $generic_user_auth = {

    # ssh-keygen -t ed25519 -f ssh.user.$username.key -C $username
    # send resulting ssh.username.key to user and delete it afterwards
    # move the ssh.username.key.pub to the secrets volume and enter a reference here
    SSH       => { PUB => [qr/(.+)/x] },
    WIREGUARD => { PUB => [qr/(.+)/x] },

    # google-authenticator -t -f -D -u -w 10 -s gauth.username.key
    # and hand the codes to the user
    GAUTH => { PUB => [qr/(.+)/x] },

    # follow the ipsec.pw script in tools
    VPN => {
        CERT => [qr/(.*)/x],
        PRIV => [qr/(.*)/x],
    }
};

my $check_user = {
    '*' => {
        $generic_user->%*,
        CLUSTER => {
            '*' => {
                '*' => {

                    $generic_user_auth->%*
                }
            }
        },
    }
};

my $check_group = { '*' => { GID => [qr/^(\d+)/x] }, };

#####################

sub _get_gids ($group) {

    my $gids = {};
    foreach my $group_name ( keys $group->%* ) {
        my $gid = $group->{$group_name}->{GID};
        die "ERROR: GID $gid of group $group_name is already used by group $gids->{$gid}" if ( exists $gids->{$gid} );
        $gids->{$gid} = $group_name;
    }
    return $gids;
}

sub _validate_accounts ($accounts) {

    my $groups    = delete $accounts->{group};
    my $used_uids = {};
    my $used_gids = _get_gids($groups);

    for my $type ( keys $accounts->%* ) {

        my $account_type = $accounts->{$type};

        for my $k ( keys $account_type->%* ) {

            my $account      = $account_type->{$k};
            my $account_name = $account->{NAME};
            my $account_gid  = $account->{GID};
            my $account_uid  = $account->{UID};

            die "ERROR: GID $account_gid of account $account_name does not exist" unless ( exists( $used_gids->{$account_gid} ) );
            die "ERROR: UID $account_uid of account $account_name is already used by $used_uids->{$account_uid}" if ( exists( $used_uids->{$account_uid} ) );

            $used_uids->{$account_uid} = $account_name;
        }
    }

    $accounts->{group} = $groups;
    return ($accounts);
}

sub _assemble_accounts ($accounts) {

    my $groups             = delete $accounts->{group};
    my $assembled_accounts = {};

    foreach my $k ( keys $accounts->{user}->%* ) {

        my $account      = $accounts->{user}->{$k};
        my $account_name = $account->{NAME};
        my $clusters     = delete $account->{CLUSTER};

        foreach my $cluster_name ( keys $clusters->%* ) {

            my $machines = $clusters->{$cluster_name};

            foreach my $machine_name ( keys $machines->%* ) {

                $assembled_accounts->{$cluster_name}->{$machine_name}->{USER_ACCOUNTS}->{USERS}->{$account_name} =
                  { $account->%*, $clusters->{$cluster_name}->{$machine_name}->%* };

                # groups are considered system accounts, as there is no point to handle user groups different.
                # also, all clusters gain all the groups, as IDs are global
                # as there must be a system account on every cluster, its safe to assume that we dont miss any cluster
                $assembled_accounts->{$cluster_name}->{$machine_name}->{USER_ACCOUNTS}->{GROUPS} = $groups;
            }
        }
    }
    return $assembled_accounts;
}

sub import_loader ( $debug, $query ) {

    my $config_path     = $query->('CONFIG_PATH');
    my $loaded_accounts = load_config( read_config( $debug, $config_path ) );
    my $accounts        = _validate_accounts(
        {
            group => check_config(
                $debug,
                {
                    name       => 'Groups',
                    config     => $loaded_accounts->{group},
                    definition => $check_group,
                    force_all  => 1
                }
            ),
            user => check_config(
                $debug,
                {
                    name       => 'User Accounts',
                    config     => $loaded_accounts->{user},
                    definition => $check_user
                }
            ),
        }
    );

    my $assembled_accounts = _assemble_accounts($accounts);

    return {
        state => {
            accounts => sub () {
                return dclone $assembled_accounts;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks ($self) {

    return {
        name    => 'Accounts',
        require => [],
        loader  => \&import_loader,
        data    => { CONFIG_PATH => 'CONFIG_PATH', }
    };
}

