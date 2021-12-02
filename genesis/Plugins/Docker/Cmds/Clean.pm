package  Plugins::Docker::Cmds::Clean;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd);

# Export
our @EXPORT_OK = qw(import_clean);

sub _clean_repo ( $query, @ ) {

    my $repo = $query->('docker_image_list');

    # now devide it in two lists: latest and rest
    my $latest = {};
    my $rest   = [];

    foreach my $img ( $repo->@* ) {

        my $tag  = $img->{TAG};
        my $name = $img->{REPOSITORY};

        #     next if ( $name eq '<none>' or $tag eq '<none>' );

        if ( exists( $latest->{$name} ) && $latest->{$name} ne '<none>' ) {

            if ( $latest->{$name} > $tag ) {

                my $mark = join ':', $name, $tag;
                print_table 'marked for deletion', ' ', ": $mark\n";
                push $rest->@*, $mark;
            }
            else {
                my $mark = join ':', $name, $latest->{$name};
                print_table 'marked for deletion', ' ', ": $mark\n";
                push $rest->@*, $mark;
                $latest->{$name} = $tag;
            }

        }
        else {

            $latest->{$name} = $tag;
        }

    }

    #   say Dumper $latest, $rest;
    my $delete = join ' ', $rest->@*;
    unless ($delete) {
        say 'Nothing to delete';
        return;
    }
    run_cmd("docker rmi $delete");
    return;
}

###############################################
# Frontend Functions

sub import_clean () {

    my $struct = {
        clean => {
            docker => {
                CMD  => \&_clean_repo,
                DESC => 'remove all but latest images from docker repository',
                HELP => ['remove all but latest images from docker repository'],
                DATA => {
                    docker_image_list => 'state docker_image_list'

                }
            }
        }
    };

    return $struct;
}
1;

