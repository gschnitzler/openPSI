package Plugins::Build::Cmds::Save;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

#use Plugins::Docker::Libs::Docker::GetImage qw(get_docker_images);
use PSI::RunCmds qw(run_cmd);
use PSI::Tag qw(get_tag);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(import_save);

# sub _get_docker_imagetree {

#     my $Image = shift;
#     my $list = get_docker_images( undef, '-a' );

#     my $leaves = [];
#     my $root  = [];

#     #  say Dumper $list;
#     foreach my $i ( $list->@* ) {

#         my $rep = delete( $i->{REPOSITORY} );
#         my $tag = delete( $i->{TAG} );
#         $i->{NAME} = join( ':', $rep, $tag ) if ( $tag ne '<none>' && $rep ne '<none>' );
#         open( my $inspect, '-|', "docker inspect -f '{{.Parent}}' $i->{'IMAGE ID'} 2>&1" )
#             or die 'could not open docker cmd';
#         $i->{PARENT} = readline $inspect;
#         chomp $i->{PARENT};
#         close $inspect;

#         delete $i->{'VIRTUAL SIZE'};
#         delete $i->{'CREATED'};
#         if ( $i->{PARENT} ) {
#             push $leaves->@*, $i;
#         }
#         else {
#             delete $i->{PARENT};
#             push $root->@*, $i;
#         }
#     }

#     die 'multiple/no roots found' unless ( scalar $root->@* == 1 );

#     my $tree = { "$root->[0]->{'IMAGE ID'}" => { NAME => $root->[0]->{'NAME'} } };

#     my $find_leaves = sub {
#         my ( $k, $v, $key_list, $item ) = @_;

#         my $parent = $item->{PARENT};
#         my $self   = $item->{'IMAGE ID'};
#         if ( $k eq $parent ) {

#             $v->{$self} = {};
#             $v->{$self}->{NAME} = $item->{NAME} if ( exists $item->{NAME} );
#             return 1;
#         }
#         return 0;
#     };

#     # protect against endless loops
#     # max_i is just a random guess.
#     # the approach involved does not suit huge lists anyway. so its good for now
#     my $max_i = ( scalar keys $leaves->@* ) * ( scalar keys $leaves->@* );
#     my $i = 0;

#     while ( $leaves->@* ) {

#         $i++;
#         my $leaf = shift $leaves->@*;

#         #say "leaf: $leaf";
#         push $leaves->@*, $leaf unless ( fill_structure( $tree, [], $find_leaves, $leaf ) );

#         die "ERROR: dependencies could not be resolved within $max_i iterations, giving up" if ( $i > $max_i );
#     }

#     return $tree;

# }

# sub _get_docker_imgpath {

#     my $image = shift;
#     my @names = ();
#     my $path  = [];

#     my $repo = _get_docker_imagetree($image);

#     #    $Data::Dumper::Indent = 1;
#     #    say Dumper $repo;

#     my $filter_content = sub {
#         my ( $k, $v, $key_list ) = @_;

#         #           say "$k, $v";
#         if ( $k eq 'NAME' && $v =~ /^$image/x ) {

#             #                say "hit $images in @$key_list";
#             push $path->@*, $key_list->@*;
#             pop $path->@*;    # remove NAME
#         }
#     };

#     # extract the docker path to image
#     walk_templates( $repo, [], $filter_content );

#     #      say Dumper $path;

#     my @rpath = reverse( $path->@* );

#     #  my $hpath = [];
#     my $conv_path = sub {
#         my ( $k, $v, $key_list, $direction ) = @_;

#         return 1 if ( scalar( $direction->@* ) == 0 );
#         my $point = pop $direction->@*;

#         if ( $k eq $point ) {

#             if ( exists( $v->{NAME} ) ) {
#                 push( @names, $v->{NAME} );
#             }
#             return 0;
#         }
#         else {
#             push $direction->@*, $point;
#             return 0;
#         }
#     };

#     # convert docker path to docker image names
#     walk_structure( $repo, [], $conv_path, \@rpath );

#     return @names;
# }

sub _save_images ( $query, @args ) {

    my $image = shift @args;

    print_table( 'Marked for save ', ' ', ': ' );

    my $imgdir = $query->('image_path');
    my $repo   = $query->('image_list');
    my @names  = ();

    #######
    # i think saving specific image paths is pointless, so i did not port this to PSI 2.0
    #######
    $image = 'all';

    # unless ($image) {
    #     say 'no image given';
    #     return 1;
    # }
    #  if ( $image eq 'all' ) {
    for ( $repo->@* ) {
        push @names, $_->{NAME} if ( $_->{NAME} );
    }

    # push @names, join( ':', $_->{REPOSITORY}, $_->{TAG} ) for ( $repo->@* );
    # }
    # else {
    #@names = _get_docker_imgpath($image);
    #  }

    unless ( scalar(@names) ) {
        say 'ERROR: NO IMAGES FOUND';
        return 1;
    }

    my $tosave = join( ' ', @names );

    say $tosave;

    my $datestring = get_tag;
    my $imgname = join( '', 'docker_', $image, '___', $datestring, '.tar.xz' );

    print_table( 'Saving tree', $image, ": $imgdir/$imgname" );

    run_cmd("docker save $tosave | xz -z -1 > $imgdir/$imgname");
    say "\nOK";
    #my $di = _get_dockerfiles( $state, $dockerfiles );
    #my $tars = save_images( $di, $state->{paths}->{DATA}->{IMAGES} );
    #merge_images( $tars, $state->{paths}->{DATA}->{IMAGES} );
    return;
}

sub import_save () {

    my $struct = {
        docker => {
            save => {
                CMD  => \&_save_images,
                DESC => 'saves docker images',
                HELP => [
                    'saves all docker images'

                      #   'usage:',
                      #   'docker save <image>',
                      #   'save <image> and its childs to disk',
                      #   'if <image> is all, then operation is taken on all known images'
                ],
                DATA => {
                    image_path => 'paths data IMAGES',
                    image_list => 'state docker_image_list'
                }
            }
        }
    };

    return $struct;
}

1;
