package Plugins::Build::Cmds::List;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Slice qw(slice_tree);
use IO::Templates::Parse qw(get_variable_tree);

# Export
our @EXPORT_OK = qw(import_list);

sub _list ( $query, @args ) {

    my $data          = $query->('state');
    my @variables     = ();
    my $all_variables = {};

    # get all templates
    my $cond = sub ($branch) {
        return 1 if ref $branch->[0] eq 'HASH' && exists $branch->[0]->{CONTENT};
        return 0;
    };

    # dont try to parse genesis
    delete $data->{genesis};

    foreach my $file ( slice_tree( $data, $cond ) ) {
        push @variables, get_variable_tree( $file->[0]->{CONTENT} );
    }

    foreach my $entry (@variables) {

        my $var = join( '.', $entry->[1]->@* );
        $all_variables->{$var} = '' unless exists( $all_variables->{$var} );
    }

    foreach my $k ( sort keys $all_variables->%* ) {
        say $k;
    }
    return;
}

###########################################
# frontend
#
sub import_list () {

    my $struct->{list}->{template}->{variables} = {

        CMD  => \&_list,
        DESC => 'compiles a list of all TT variables',
        HELP => ['compiles a list of all TT variables'],
        DATA => { state => 'state', }
    };

    return $struct;
}
1;
