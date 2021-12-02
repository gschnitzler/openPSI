package Plugins::Docker::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use PSI::RunCmds qw(run_cmd);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(import_update);

sub _update_images ( $query, @ ) {

    my $images = $query->('images');

    unless ( kexists( $images, 'docker', 'all', 'latest' ) ) {
        say 'ERROR: no image found';
        return 1;
    }

    my $image = $images->{docker}->{all}->{latest};
    print_table( 'Loading Images from ', $image, ': ' );
    run_cmd("docker load --quiet --input $image > /dev/null");
    say 'OK';
    return;
}

sub import_update () {

    my $struct = {
        update => {
            docker => {
                CMD  => \&_update_images,
                DESC => 'updates docker images',
                HELP => [ 'usage:', 'update docker', 'installs new latest images' ],
                DATA => { images => 'state images' }
            }
        }
    };

    return $struct;
}

1;
