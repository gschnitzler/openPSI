package Plugins::Build::Lib::Archive;

use ModernStyle;
use Exporter qw(import);
use Archive::Tar;
use Data::Dumper;

use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_system);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(build_archive);

sub build_archive ( $p) {

    my $files        = $p->{files};
    my $dirs         = $p->{dirs};
    my $archive_name = $p->{archive_name};
    my $archive_path = $p->{archive_path};

    print_table( 'Assembling Archive', $archive_name, ': ' );

    die 'ERROR: incomplete parameters' if ( !$files || !$archive_name || !$archive_path );
    my $full_archive_path = join( '', $archive_path, '/', $archive_name, '.tar' );
    my $chown             = 'root:root';
    my $tar               = Archive::Tar->new;

    foreach my $file ( $files->@* ) {

        # ignore all flags except CHMOD.
        my $content  = $file->{CONTENT};
        my $chmod    = $file->{CHMOD};
        my $filename = $file->{LOCATION};

        $tar->add_data( $filename, join( "\n", $content->@* ) );
        $tar->chown( $filename, $chown );
        $tar->chmod( $filename, $chmod );
    }

    foreach my $dir ( $dirs->@* ) {

        # ignore all flags except CHMOD.
        my $chmod    = $dir->{CHMOD};
        my $filename = $dir->{LOCATION};
        next unless $filename;    # / cant be changed in tar
        $tar->chown( $filename, $chown );
        $tar->chmod( $filename, $chmod );
    }

    {
        local ( $?, $! );         # tar write leaks $!, unlink might
        unlink($full_archive_path) or die 'unlink failed' if ( file_exists $full_archive_path );
        $tar->write($full_archive_path);    # no xz compression supported
    }
    run_system("zstd --rm -qfz -6 $full_archive_path");    # -f in case file exists

    say 'OK';
    return;
}

1;
