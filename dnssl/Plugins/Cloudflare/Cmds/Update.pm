package Plugins::Cloudflare::Cmds::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(read_stdin print_line);
use API::Cloudflare qw(add_dns_cloudflare del_dns_cloudflare list_dns_cloudflare);

use Plugins::Cloudflare::Lib::Diff qw(diff_dns);
use Plugins::Cloudflare::Lib::Print qw(print_dns);

# Export
our @EXPORT_OK = qw(import_update);

#######################################

sub _update_dns ( $query, @) {

    my $dns_config      = $query->('dns_config');
    my $cloudflare_keys = $query->('get_cloudflare_keys');
    my $dns_cloudflare  = list_dns_cloudflare $cloudflare_keys;
    my $action_tree     = diff_dns( $dns_cloudflare, $dns_config );

    print_line 'Delete from Cloudflare';
    print_dns $action_tree->{DELETE};

    print_line 'Add to Cloudflare';
    print_dns $action_tree->{ADD};

    while ( my $line = read_stdin( 'Are you sure you want to apply these changes? [yes|no] ', -style => 'bold red' ) ) {
        last   if $line eq 'yes';
        exit 0 if ( $line eq 'no' );
    }

    my $del_result = del_dns_cloudflare( $cloudflare_keys, $action_tree->{DELETE} );
    my $add_result = add_dns_cloudflare( $cloudflare_keys, $action_tree->{ADD} );

    return;
}

###########################################
# frontend
#
sub import_update () {

    my $struct = {};

    $struct->{update}->{dns} = {

        CMD  => \&_update_dns,
        DESC => 'Updates Cloudflare DNS',
        HELP => ['Updates Cloudflare DNS'],
        DATA => {
            get_cloudflare_keys => 'state cloudflare',
            dns_config          => 'state dns',
        }
    };

    return $struct;
}

1;
