package Plugins::Build::Filter::Secrets;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use InVivo qw(kexists);
use Tree::Slice qw(slice_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(add_secrets add_secrets_tree);

sub add_secrets_tree ( $secrets, $tree ) {

    my $counter = 0;
    my $missing = {};
    my $cond    = sub ($branch) {
        say Dumper $branch unless defined $branch->[0];
        return 1 if ( ref $branch->[0] eq '' && $branch->[0] =~ /^SECRETS:/x );
        return 0;
    };

    foreach my $entry ( slice_tree( $tree, $cond ) ) {

        my $branch   = $entry->[0];
        my $path     = $entry->[1];
        my ($secret) = $branch =~ /^SECRETS:(.*)/x;

        next unless $secret;
        unless ( exists( $secrets->{$secret} ) ) {
            push $missing->{$secret}->@*, join( '->', $path->@* );
            next;
        }

        $counter++;
        my $current      = $tree;
        my $last_element = pop $path->@*;
        foreach my $key ( $path->@* ) {
            $current = $current->{$key};
        }

        if ( !kexists( $secrets, $secret, 'BASE64' ) || !$secrets->{$secret}->{BASE64} ) {
            $current->{$last_element} = join( "\n", $secrets->{$secret}->{CONTENT}->@* );
        }
        else {
            # binary blobs need special care. so add a special keyword and process it later.
            $current->{$last_element}                  = {};
            $current->{$last_element}->{BINARY_SECRET} = join( "\n", $secrets->{$secret}->{CONTENT}->@* );
            $current->{$last_element}->{__IGNORE__}    = 'omit BINARY_SECRET in templates. its used internally';
        }
    }

    return $counter if ( scalar keys $missing->%* == 0 );
    say '';
    foreach my $secret ( sort keys $missing->%* ) {
        my $notfound = $missing->{$secret};
        foreach my $e ( $notfound->@* ) {
            say "$secret: $e";
        }
    }
    die 'ERROR: secrets not found';
}

# so this is a bit of a mess.
# SECRETS can be anywhere. thus this generic search and replace tool.
# and secrets in general are just blobs, not files. so it makes sense to loose all metainfo here (CHMOD, LOCATION etc)
# however, binary secrets are now base64 encoded and need to be decoded on use.
# every plugin that uses a binary secret should do that on its own.
# for templates its a bit tricky. see below
sub add_secrets ( $tree, $secrets ) {

    # add the rest
    foreach my $cluster_name ( keys( $tree->%* ) ) {

        my $cluster = $tree->{$cluster_name};

        foreach my $machine_name ( keys $cluster->%* ) {
            my $counter = 0;
            my $machine = $cluster->{$machine_name};
            print_table( 'Add Secrets', "$cluster_name/$machine_name", ': ' );

            $counter = add_secrets_tree( $secrets, $machine->{machine} );
            $counter = $counter + add_secrets_tree( $secrets, $machine->{service} );
            $counter = $counter + add_secrets_tree( $secrets, $machine->{container} );
            $counter = $counter + add_secrets_tree( $secrets, $machine->{cloudflare} );

            say "$counter added";
        }
    }
    return;
}
