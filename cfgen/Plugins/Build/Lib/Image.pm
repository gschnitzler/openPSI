package Plugins::Build::Lib::Image;

use ModernStyle;
use Exporter qw(import);

use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd);
use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw(build_image);

sub build_image ( $p ) {

    die 'ERROR: invalid parameters for build_image'
      if ( !exists $p->{to_file}
        || !exists $p->{to_dir}
        || !exists $p->{from_dir}
        || !exists $p->{mount}
        || !exists $p->{tmp_dir} );

    print_table( 'Assembling Image', $p->{to_file}, ': ' );

    my $mount   = $p->{mount};
    my $from_fp = $p->{from_dir};
    my $tmp_dir = $p->{tmp_dir};
    my $to_fp   = join( '/', $p->{to_dir}, $p->{to_file} );
    my $tmp_fp  = join( '/', $tmp_dir, $p->{to_file} );

    die 'ERROR: Mount path invalid'       if ( !dir_exists $mount );
    die 'ERROR: Source path invalid'      if ( !dir_exists $from_fp );
    die 'ERROR: Destination path invalid' if ( !dir_exists $p->{to_dir} );
    die 'ERROR: Temp path invalid'        if ( !dir_exists $tmp_dir );
    
    run_cmd(
        # 20 mb is save for btrfs, don't make it smaller
        # the more configuration is added, the bigger the image has to be.
        # currently, 40mb is minimum
	"rm -f $tmp_fp > /dev/null 2>&1",
        "dd of=$tmp_fp bs=40M seek=1 count=0 > /dev/null 2>&1",
        "mkfs.btrfs -M $tmp_fp > /dev/null 2>&1",
        "mount $tmp_fp $mount",
        "cp -Rfp $from_fp/* $mount",

        #"chmod -R 500 $mount",
        #"chown -R root:root $mount",
        'sync',
        'sleep 1',
        "umount -lf $mount",
        "xz -z -1 -k -f $tmp_fp",
        "mv $tmp_fp.xz $to_fp.xz",
        "chmod 400 $to_fp.xz",
    );
    say 'OK';
    return;
}

1;
