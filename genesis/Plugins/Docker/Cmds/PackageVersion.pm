package Plugins::Docker::Cmds::PackageVersion;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::RunCmds qw(run_cmd);
use PSI::Console qw(print_table print_line);
use PSI::Parse::Packages qw(read_pkgversion compare_pkgversion);

our @EXPORT_OK = qw(import_packageversion);

#######################################################

sub _compare_dockerversion ( $query, @ ) {

    my $image_list   = $query->('image_list');
    my $docker_path  = $query->('docker_path');
    my $pkgversion_f = $query->('pkgversion');

    $docker_path = join '/', $docker_path, 'btrfs', 'subvolumes';
    my $list = {};

    foreach my $image ( $image_list->@* ) {

        my $fullname = $image->{NAME};
        my $name     = $image->{REPOSITORY};
        my $tag      = $image->{TAG};

        next if ( $name eq '<none>' );

        my $token = join '_', 'token', $fullname;
        my $container_name = join '_', $name, 'find';
        my $container_dir = $query->(
            'find_image',
            {   path           => $docker_path,
                container_name => $container_name,
                parent_image   => $fullname,
                token          => $token,
            }
        );
        $list->{$name}->{$tag} = read_pkgversion( join '', $container_dir, $pkgversion_f );

        print_table( 'Removing Container', $fullname, ': ' );
        run_cmd("docker rm $container_name > /dev/null 2>&1");
        say 'OK';

    }

    # if there is no output, then check if there are two sets of dockerimages in the repo :)

    foreach my $image_name ( keys( $list->%* ) ) {

        my $image            = $list->{$image_name};
        my @tags             = sort keys( $image->%* );
        my $latest_image_tag = pop @tags;
        my $latest_image     = delete( $image->{$latest_image_tag} );

        foreach my $tag ( keys $image->%* ) {

            my $pkgs = delete $image->{$tag};
            print_line("$image_name:$tag -> $image_name:$latest_image_tag");

            unless ($pkgs) {
                say "$image_name:$tag does not contain a pkgversion file";
                next;
            }
            compare_pkgversion( $pkgs, $latest_image );
            print "\n";
        }
    }
    return;
}

sub import_packageversion () {

    my $struct = {
        compare => {
            docker => {
                version => {
                    CMD  => \&_compare_dockerversion,
                    DESC => 'compare package version information for sets of docker images',
                    HELP => [ 'compare package version information for sets of docker images', 'no output means there are no 2 sets of images' ],
                    DATA => {
                        image_list  => 'state docker_image_list',
                        find_image  => 'state docker_find_image',
                        docker_path => 'paths data DOCKER',
                        pkgversion  => 'paths hostos PKGVERSION',
                    }
                }
            }
        }
    };

    return $struct;
}
1;
