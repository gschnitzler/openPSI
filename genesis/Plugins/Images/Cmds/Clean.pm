package Plugins::Images::Cmds::Clean;

use ModernStyle;
use Exporter qw(import);
use File::Find;
use Data::Dumper;

use PSI::Console qw(print_table);
use Tree::Slice qw(slice_tree);

# Export
our @EXPORT_OK = qw(import_clean);

sub _clean_images ( $query, @args ) {

    my $images = $query->('images');
    my $keep   = {};

    my $cond = sub ($branch) {

        if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{latest} ) ) {
            return 1;
        }
        return 0;
    };

    foreach my $result ( slice_tree( $images, $cond ) ) {

        my $entries = $result->[0];
        my $path    = $result->[1];

        my $latest = delete( $entries->{latest} );
        $keep->{$latest} = 1;

        foreach my $entry ( keys $entries->%* ) {

            my $item = $entries->{$entry};

            print_table( 'Deleting:', $item, ': ' );

            if ( exists( $keep->{$item} ) ) {
                say 'No';
            }
            else {
                say 'Yes';
                unlink $item or die 'unlink failed';
            }
        }
    }
    return;
}

###############################################
# Frontend Functions

sub import_clean () {

    my $struct = {
        clean => {
            images => {
                CMD  => \&_clean_images,
                DESC => 'deletes all but latest images',
                HELP => ['deletes all but latest images'],
                DATA => { images => 'state images' }
            }
        }
    };

    return ($struct);
}
1;

