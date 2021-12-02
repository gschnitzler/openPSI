package Plugins::Docker::Libs::GetImage;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Iterators qw(array_iterator);
use Tree::Slice qw(slice_tree);
use PSI::RunCmds qw(run_open);

our @EXPORT_OK = qw(get_docker_image_tree get_docker_image_list);

# sub get_latest_version ($image){

#     # get latest real gentoo base
#     my $base = get_docker_images($image);

#     my @versions = ();
#     foreach my $img ( $base->@* ) {
#         push @versions, $img->{TAG};
#     }

#     @versions = sort @versions;
#     return pop @versions;
# }

# sub get_docker_images ($image, $option){

#     $option = '' unless ($option);
#     open( my $img, '-|', "docker images $option --no-trunc=true 2>&1" )
#         or die 'could not open docker cmd';
#     my @docker = <$img>;
#     close $img;

#     my @names = split( /\s{2,}/x, shift @docker );
#     chomp $names[-1];

#     my $list = [];
#     while ( my $line = shift @docker ) {

#         chomp $line;
#         next if ( $image && $line !~ /^$image/x );

#         my @line_elm = split( /\s{2,}/x, $line );

#         die 'ERROR: line has not same elements as header' unless ( @names == @line_elm );
#         my $h = {};

#         my $it = array_iterator( \@names, \@line_elm );
#         while ( my ( $n_elm, $l_elm ) = $it->() ) {

#             # next unless ($n_elm && $l_elm);
#             $h->{$n_elm} = $l_elm;
#         }

#         push $list->@*, $h;

#     }

#     #    close $img;

#     return $list;
# }

sub _get_docker_image () {

    my @docker = run_open 'docker images -a --no-trunc=true 2>&1';
    my @names  = split( /\s{2,}/x, shift @docker );
    my $leaves = {};
    my $tree   = {};
    my @list   = ();

    while ( my $line = shift @docker ) {

        my @line_elm = split( /\s{2,}/x, $line );

        die 'ERROR: line has not same elements as header' unless ( @names == @line_elm );

        # match header elements with line elements and create a hash
        my $h  = {};
        my $it = array_iterator( \@names, \@line_elm );
        while ( my ( $n_elm, $l_elm ) = $it->() ) {

            # next unless ($n_elm && $l_elm);
            $h->{$n_elm} = $l_elm;
        }

        $h->{NAME} = join( ':', $h->{REPOSITORY}, $h->{TAG} ) if ( $h->{TAG} ne '<none>' && $h->{REPOSITORY} ne '<none>' );
        my ( $parent, @rest ) = run_open "docker inspect -f '{{.Parent}}' $h->{'IMAGE ID'} 2>&1";
        $h->{PARENT} = $parent;

        if ( $h->{PARENT} ) {
            push $leaves->{ $h->{'PARENT'} }->@*, $h;
        }
        else {
            $tree->{ $h->{'IMAGE ID'} } = $h;
        }
        push @list, $h;
    }

    return ( { roots => $tree, leaves => $leaves, list => \@list } );
}

#####################################

sub get_docker_image_list () {

    my $img = _get_docker_image();
    return $img->{list};
}

sub get_docker_image_tree () {

    #say Dumper $tree, $leaves;
    my $img        = _get_docker_image();
    my $tree       = delete( $img->{roots} );
    my $leaves     = delete $img->{leaves};
    my @references = ();

    foreach my $key ( keys $tree->%* ) {
        push @references, $tree->{$key};
    }

    while ( my $ref = shift @references ) {

        #say "NEW: $ref->{'IMAGE ID'}";
        #say Dumper $ref;
        if ( exists $leaves->{ $ref->{'IMAGE ID'} } ) {

            my $entry = delete $leaves->{ $ref->{'IMAGE ID'} };
            foreach my $image ( $entry->@* ) {
                $ref->{LEAVES}->{ $image->{'IMAGE ID'} } = $image;
                push @references, $ref->{LEAVES}->{ $image->{'IMAGE ID'} };

                #       say 'ADD: ', $ref->{LEAVES}->{ $image->{'IMAGE ID'}}->{'IMAGE ID'};
                #say Dumper $ref->{LEAVES}->{ $image->{'IMAGE ID'}};
            }
        }

        #else{
        #    say "NOT: $ref->{'IMAGE ID'} ";
        #    say Dumper $ref;
        #   # push @references, $ref;
        #}

    }

    # pad in real parent names
    my $cond = sub  ($branch) {
        if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{NAME} ) ) {
            return 1;
        }
        return 0;
    };

    for my $entry ( slice_tree( $tree, $cond ) ) {
        my $ref     = $entry->[0];
        my $path    = $entry->[1];
        my $pointer = $tree;
        my $parent;
        next if ( scalar $path->@* < 1 );

        foreach my $key ( $path->@* ) {

            $parent  = $pointer->{NAME} if ( exists( $pointer->{NAME} ) );
            $pointer = $pointer->{$key};
        }
        $ref->{REAL_PARENT} = $parent;
    }

    #say Dumper $tree;
    return $tree;
}

1;
