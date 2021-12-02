package Plugins::Docker::Libs::GetImageLayer;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::Dir qw(get_directory_list);
use PSI::RunCmds qw(run_cmd);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(find_image_layer);

# the idea here is to start a container to get a valid BTRFS subvolume,
# which can then be mangled with by the caller.
# therefor removing that container is up to the caller.
sub find_image_layer ( $p ) {

    my $path           = $p->{path};
    my $container_name = $p->{container_name};
    my $parent_image   = $p->{parent_image};
    my $token          = $p->{token};

    die 'ERROR: insufficient arguments' unless ( $path && $container_name && $parent_image && $token );
    print_table( 'Acquiring BTRFS Layer', "$container_name ", ': ' );
    run_cmd("docker run --name $container_name -i --restart=no -d=false --net=none -t $parent_image touch /$token > /dev/null 2>&1");

    my $root = get_directory_list($path);

    foreach my $layer ( keys $root->%* ) {

        my $cur_folder = join( '/', $path, $layer );
        my $files_in_cur_folder = get_directory_list($cur_folder);
        if ( exists( $files_in_cur_folder->{$token} ) ) {
            unlink("$cur_folder/$token") or die "could not unlink $cur_folder/$token";
            say $cur_folder;
            return ($cur_folder);
        }
    }
    die "ERROR: could not find $token in $path";
}
1;
