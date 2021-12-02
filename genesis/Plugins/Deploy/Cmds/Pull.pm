package Plugins::Deploy::Cmds::Pull;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::File qw(write_file);
use Plugins::Deploy::Libs::Machines qw(list_machines);
use Plugins::Deploy::Libs::SSH qw(scp_pull);

our @EXPORT_OK = qw(import_pull);

#############

sub ssh_pull ( $query, @args ) {

    my ( $mode, $wanted, $id ) = @args;

    unless ($id) {
        say 'ERROR: not enough arguments';
        return 1;
    }

    if ( $mode ne 'normal' && $mode ne 'bootstrap' ) {
        say "ERROR: unrecognized mode '$mode'";
        return 1;
    }

    my ( $network, $machine ) = split /\//, $id;

    die 'ERROR: wrong arguments' if ( !$network || !$machine );

    my $image_path   = $query->('image_path');
    my $others       = $query->('others');
    my $mro_user     = $query->('mro_user');
    my $mro_key_path = $query->('mro_key_path');
    my $mro_key_priv = $query->('mro_key_priv');
    my $machines     = list_machines(
        {
            nodes        => $query->('nodes'),
            other_nodes  => $others->{$network},
            own_group    => $query->('group'),
            wanted_group => $network,
            mro_user     => $mro_user,
            mro_key      => $mro_key_path,
            mode         => 'normal',              # do not confuse $mode with this. this is the mode of the ssh target host.
                                                   # when pulling, the target is always in normal mode (there is nothing to pull from a bootstrap node)
        }
    );

    unless ( exists( $machines->{$machine} ) ) {
        say "ERROR: $id not found";
        return 1;
    }

    # create key and replace key path with a valid one in bootstrap mode
    if ( $mode eq 'bootstrap' ) {
        my $key_path = '/root/key';
        write_file(
            {
                PATH    => $key_path,
                CONTENT => ["$mro_key_priv\n"],
                CHMOD   => 400
            }
        );
        $machines->{$machine}->{keyfile} = $key_path;
    }

    scp_pull( $machines->{$machine}, $image_path, $wanted );
    return;
}

################
sub import_pull () {

    my %require_all = (
        image_path   => 'paths data IMAGES',
        nodes        => 'machine nodes',
        group        => 'machine self GROUP',
        others       => 'machine adjacent',
        mro_user     => 'machine self NAMES MRO',
        mro_key_path => 'machine self COMPONENTS SERVICE ssh HOSTKEYS ED25519 PRIVPATH',
        mro_key_priv => 'machine self COMPONENTS SERVICE ssh HOSTKEYS ED25519 PRIV'

    );

    my $struct = {
        pull => {
            CMD  => \&ssh_pull,
            DESC => 'pulls images from adjacent machines',
            HELP => [
                'pull <normal|bootstrap> <image> <network/machine>',
                'ie: pull normal genesis build/buildhost',
                'see \'images state\' for image to pull',
                'normal: the machine issuing pull has valid hostkeys',
                'bootstrap: the machine issuing pull does not have a valid hostkey',
                'the later is true when pulling images in a rescue environment.'
            ],
            DATA => {%require_all}
        },
    };

    return $struct;
}

1;

