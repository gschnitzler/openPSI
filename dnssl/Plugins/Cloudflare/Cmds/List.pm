package Plugins::Cloudflare::Cmds::List;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_line);
use API::Cloudflare qw(list_dns_cloudflare);

use Plugins::Cloudflare::Lib::Diff qw(diff_dns);
use Plugins::Cloudflare::Lib::Print qw(print_dns);

our @EXPORT_OK = qw(import_list);

#######################################

sub _dump($tree) {

    local $Data::Dumper::Indent    = 0;
    local $Data::Dumper::Quotekeys = 0;
    say Dumper $tree;
    return;
}

sub _list_cloudflare ( $query, @args ) {

    print_dns list_dns_cloudflare $query->('get_cloudflare_keys');
    return;
}

sub _dump_cloudflare ( $query, @args ) {

    _dump list_dns_cloudflare $query->('get_cloudflare_keys');
    return;
}

sub _list_config ( $query, @args ) {

    my $dns_config = $query->('dns_config');
    print_dns $dns_config;
    return;
}

sub _dump_config ( $query, @args ) {

    my $dns_config = $query->('dns_config');
    _dump $dns_config;
    return;
}

sub _compare_dns ( $query, @args ) {

    my $dns_config     = $query->('dns_config');
    my $dns_cloudflare = list_dns_cloudflare $query->('get_cloudflare_keys');
    my $action_tree    = diff_dns( $dns_cloudflare, $dns_config );

    print_line 'Delete from Cloudflare';
    print_dns $action_tree->{DELETE};

    print_line 'Add to Cloudflare';
    print_dns $action_tree->{ADD};

    return;
}

###########################################
# frontend
#

sub import_list () {

    my $struct = {};

    $struct->{list}->{dns}->{cloudflare} = {

        CMD  => \&_list_cloudflare,
        DESC => 'list all cloudflare dns entries',
        HELP => ['lists all known cloudflare DNS entries'],
        DATA => { get_cloudflare_keys => 'state cloudflare', }
    };

    $struct->{dump}->{dns}->{cloudflare} = {

        CMD  => \&_dump_cloudflare,
        DESC => 'Dumps all cloudflare dns entries',
        HELP => ['Dumps all known cloudflare DNS entries'],
        DATA => { get_cloudflare_keys => 'state cloudflare', }
    };

    $struct->{list}->{dns}->{config} = {

        CMD  => \&_list_config,
        DESC => 'list all config dns entries',
        HELP => ['lists all known entries from cluster/container config'],
        DATA => { dns_config => 'state dns', }
    };

    $struct->{dump}->{dns}->{config} = {

        CMD  => \&_dump_config,
        DESC => 'Dumps all config dns entries',
        HELP => ['Dumps all known entries from cluster/container config'],
        DATA => { dns_config => 'state dns', }
    };

    $struct->{compare}->{dns} = {

        CMD  => \&_compare_dns,
        DESC => 'diff cloudflare/config DNS entries',
        HELP => [ 'lists all known cloudflare DNS entries as well as all entries from cluster/container config', 'shows differences' ],
        DATA => {
            get_cloudflare_keys => 'state cloudflare',
            dns_config          => 'state dns',
        }
    };

    return $struct;
}

1;
