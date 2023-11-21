package Plugins::Deploy::Libs::Image;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd run_open);

our @EXPORT_OK = qw(make_image);

# megabytes added to image sizes
# btrfs needs some space
Readonly my $IMAGE_SPACE => 30;

#############

sub make_image ( $source, $target, $guid ) {

    print_table( 'Assembling', $source, ': ' );

    my ( $size, @rest ) = run_open "du -m --max-depth=0 $source";
    my @size = split /\s+/x, $size;

    #$size =~ s/\ +.*//x;

    my $dd_size = $size[0] + $IMAGE_SPACE;
    $dd_size = join '', $dd_size, 'M';

    run_cmd("dd of=$target bs=$dd_size seek=1 count=0 > /dev/null 2>&1");
    run_cmd("mkfs.btrfs -M $target > /dev/null 2>&1");
    run_cmd("mount $target /mnt");

    # this will ignore all hidden files in root (like .git)
    # run_cmd("cp -Rfp $source/* /mnt/");
    run_cmd("rsync -aHAX --exclude '.git' $source/ /mnt/");
    run_cmd("chown -R $guid /mnt/") if ($guid);
    run_cmd('sync && sleep 1 && umount /mnt');
    run_cmd("zstd -qzf -6 $target");

    $target = join '', $target, '.zst';
    say 'OK';

    return ($target);
}
