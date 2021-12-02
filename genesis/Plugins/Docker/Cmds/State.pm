package Plugins::Docker::Cmds::State;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_line);

# Export
our @EXPORT_OK = qw(import_state);

sub _state ( $query, @args ) {

    #   my $id_list      = $query->('state id_list');
    #   my $parent_image = $query->('state parent_image');
    #   my $image_name   = $query->('state image_name');
    my $docker_image_tree = $query->('docker_image_tree');
    my $docker_image_list = $query->('docker_image_list');

    #    say Dumper $id_list, $parent_image, $image_name;

    print_line('Docker System State');

    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;
    say Dumper $docker_image_tree;
    say Dumper $docker_image_list;

    return;
}

###############################################
# Frontend Functions

sub import_state () {

    my $struct = {
        docker => {
            state => {
                CMD  => \&_state,
                DESC => 'prints Docker state information',
                HELP => ['prints Docker state information'],
                DATA => {

                    docker_image_tree => 'state docker_image_tree',
                    docker_image_list => 'state docker_image_list'

                        #                id_list      => 'state docker_id_list',
                        #                parent_image => 'state docker_parent_image',
                        #                image_name   => 'state docker_image_name'

                }
            }
        }
    };

    return $struct;
}
1;

