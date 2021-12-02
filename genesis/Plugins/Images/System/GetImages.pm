package Plugins::Images::System::GetImages;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Find;

# Export
our @EXPORT_OK = qw(get_images);

sub _add_hierarchically ( $ref, $latest, @rest ) {

    my $next = shift @rest;

    # just return the last entry
    unless ($next) {

        $ref->{ $latest->{version} } = $latest->{path};
        return ($ref);
    }

    # create hashref if it does not exist yet.
    $ref->{$next} = {} unless $ref->{$next};

    # recurse with next element
    return ( _add_hierarchically( $ref->{$next}, $latest, @rest ) );
}

sub _determine_latest ($images) {

    foreach my $image ( keys $images->%* ) {

        my $comimg = $images->{$image};
        foreach my $type ( keys $comimg->%* ) {

            my @versions = sort keys $comimg->{$type}->%*;
            $comimg->{$type}->{latest} = $comimg->{$type}->{ pop @versions };
        }
    }
    return ($images);
}

####

sub get_images ( $dir, @arguments ) {

    my $images = {};
    my $regex  = qr /^([^_]+)_.*.xz$/x;
    my @files  = ();
    my $wanted = sub ( $file, $files, $regex_w ) {
        push $files->@*, $file if $file =~ m/$regex_w/x;
    };

    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink
    find( sub (@) { &$wanted( $_, \@files, $regex ) }, $dir );

    foreach my $file (@files) {

        my $f = $file;
        $f =~ s/[.]gz$//x;
        $f =~ s/[.]bz2$//x;
        $f =~ s/[.]xz$//x;
        $f =~ s/[.]tar$//x;

        my @fparts = ();

        if ( $f =~ m/([^_]+)_(.+)/x ) {
            @fparts = ( $1, $2 );
        }

        my ( $latest, $version ) = split /___/x, pop @fparts;
        push @fparts, $latest;

        unless ($version) {
            print "Warning: $file has no version, assuming latest ";
            $version = 'latest';
        }
        _add_hierarchically( $images, { version => $version, path => "$dir/$file" }, @fparts );
    }

    if ( scalar keys $images->%* >= 1 ) {
        $images = _determine_latest($images);
    }

    return ($images) if ( scalar @arguments == 0 );

    my $ref = $images;
    foreach my $arg (@arguments) {

        die "ERROR: image not found: @arguments" unless exists( $ref->{$arg} );
        $ref = $ref->{$arg};
    }
    return $ref;
}
1;
