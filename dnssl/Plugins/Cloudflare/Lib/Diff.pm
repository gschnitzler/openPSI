package Plugins::Cloudflare::Lib::Diff;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use Tree::Slice qw(slice_tree);
use Tree::Search qw(tree_search_deep);

our @EXPORT_OK = qw(diff_dns);

##################################################
# This Module should not care about record types.
# Tested for A and TXT :)
##################################################

#sub _compare_lr ( $lt, $rt, $tree_path ) {
#
#    $lt = $lt->{$_} for ( $tree_path->@* );
#    $rt = $rt->{$_} for ( $tree_path->@* );
#
#    foreach my $key ( keys $lt->%* ) {
#
#        # config and cloudflare ids can not match
#        next if $key eq 'id' || $key eq 'zone_id';
#
#        return $rt if ( $lt->{$key} ne $rt->{$key} );
#    }
#    return;
#}

sub _get_pointer ( $p, $path ) {

    my $keys     = dclone $path;
    my $last_key = pop $keys->@*;

    for my $key ( $keys->@* ) {

        $p->{$key} = {} unless exists $p->{$key};
        $p = $p->{$key};
    }
    return $p, $last_key;
}

sub _compare_tree ( $lt, $rt, $slice_cond ) {

    my $left_misses = {};

    foreach my $e ( slice_tree( $lt, $slice_cond ) ) {

        my $lt_entry = $e->[0];
        my $lt_path  = $e->[1];
        my ( $hit, $misses ) = tree_search_deep( $rt, $slice_cond, $lt_path );

        if ($misses) {
            my ( $p,  $key )  = _get_pointer( $left_misses, $lt_path );
            my ( $lp, $lkey ) = _get_pointer( $lt,          $lt_path );

            $p->{$key} = $lp->{$lkey};
        }
    }
    return $left_misses;
}

sub diff_dns ( $lt, $rt ) {

    my $slice_cond = sub ($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists $branch->[0]->{content} );
        return 0;
    };

    my $left_m  = _compare_tree( $lt, $rt, $slice_cond );
    my $right_m = _compare_tree( $rt, $lt, $slice_cond );
    my @del     = ();

    my $ignore_cond = sub ($branch) {
        if ( ref $branch->[0] eq 'HASH' && exists $branch->[0]->{IGNORE} ) {
            my ( $r, $k ) = _get_pointer( $left_m, $branch->[1] );

            #say Dumper $r->{$k};
            push @del, $branch->[1];
            delete $r->{$k};
        }
        return;
    };

    # remove ignored entries.
    slice_tree( $right_m, $ignore_cond );

    foreach my $path (@del) {

        my ( $r, $k ) = _get_pointer( $right_m, $path );
        delete $r->{$k};
    }

    return {
        DELETE => $left_m,
        ADD    => $right_m
    };
}

1;
