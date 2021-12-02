package Plugins::Build::Cmds::Clean;

use ModernStyle;
use Data::Dumper;
use Exporter qw(import);

use PSI::System::BTRFS qw(get_btrfs_subvolumes delete_btrfs_subvolume);

our @EXPORT_OK = qw(import_clean);

sub _clean_build ( $query, @args ) {

    my $builddir = $query->('builddir');
    my $volumes  = get_btrfs_subvolumes($builddir);
    my @delete   = ();

    foreach my $tag ( keys $volumes->%* ) {
        push @delete, join( ':', $_, $tag ) for keys( $volumes->{$tag}->%* );
    }

    delete_btrfs_subvolume( $builddir, @delete );

    return;
}

###############################################
# Frontend Functions

sub import_clean () {

    my $struct = {
        clean => {
            build => {
                CMD  => \&_clean_build,
                DESC => 'deletes all build snapshots',
                HELP => ['deletes all build snapshots'],
                DATA => { builddir => 'paths data BUILD' }
            }
        }
    };

    return ($struct);
}
1;

