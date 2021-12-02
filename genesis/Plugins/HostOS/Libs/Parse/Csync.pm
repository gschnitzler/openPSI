package Plugins::HostOS::Libs::Parse::Csync;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_csync);

#####################################################################

sub _gen_csync ( $config, $template, $substitutions ) {

    my $nodes            = $config->{nodes};
    my $myself           = $config->{self};
    my $container_config = $config->{container_config};

    my @cfg = ();

    push @cfg, 'nossl * *;';
    push @cfg, join( ' ', 'group', $myself->{GROUP} );
    push @cfg, '{';

    # add self
    push @cfg, join( '', 'host ', $myself->{NAMES}->{SHORT}, ';' );

    # add nodes
    foreach my $node ( keys $nodes->%* ) {

        my $node_cf = $nodes->{$node};

        #   say Dumper $node_cf;
        next if ( $node_cf->{COMPONENTS}->{SERVICE}->{csync}->{ENABLE} ne 'yes' );
        push @cfg, join( '', 'host ', $node_cf->{NAMES}->{SHORT}, ';' );

    }

    push @cfg, join( '', 'key ', $myself->{CSYNC}->{KEY}, ';' );

    foreach my $container_name ( keys $myself->{CONTAINER}->%* ) {

        foreach my $container_tag ( keys $myself->{CONTAINER}->{$container_name}->%* ) {
            next unless ( $myself->{CONTAINER}->{$container_name}->{$container_tag}->{ENABLE} eq 'yes' );
            push @cfg, join( '', 'include ', $container_config->{$container_name}->{$container_tag}->{config}->{DOCKER}->{PATHS}->{SHARED}, ';' );
        }
    }

    # push @cfg, 'action { logfile "/var/log/csync2.log"; }';
    push @cfg, 'auto younger;';
    push @cfg, '}';

    my $cf = {};
    $cf->{LOCATION} = $template->{LOCATION};
    $cf->{CHMOD}    = $template->{CHMOD};
    $cf->{CONTENT}  = \@cfg;

    my $ca = {};
    $ca->{LOCATION} = $myself->{CSYNC}->{KEY};
    $ca->{CHMOD}    = '600';
    $ca->{CONTENT}  = [ $myself->{CSYNC}->{CA} ];
    return ( $cf, $ca );
}

sub _gen_lsync ( $config, $header, $footer, $substitutions ) {

    my @cfg              = ();
    my $nodes            = $config->{nodes};
    my $myself           = $config->{self};
    my $myname           = $myself->{NAMES}->{SHORT};
    my $container_config = $config->{container_config};

    foreach my $line ( $header->{CONTENT}->@* ) {
        push @cfg, $line;
    }

    foreach my $container_name ( keys $myself->{CONTAINER}->%* ) {

        foreach my $container_tag ( keys $myself->{CONTAINER}->{$container_name}->%* ) {
            next unless ( $myself->{CONTAINER}->{$container_name}->{$container_tag}->{ENABLE} eq 'yes' );

            #      push @cfg, join( '', '["', $substitutions->{container}->{$container}->{DOCKER}->{SHARED}, '"] = ', $myname, "," );
            push @cfg, join( '', '"', $container_config->{$container_name}->{$container_tag}->{config}->{DOCKER}->{PATHS}->{SHARED}, '",' );
        }
    }

    my $last_e = pop @cfg;
    $last_e =~ s/,$//x;
    push @cfg, $last_e;

    foreach my $line ( $footer->{CONTENT}->@* ) {
        push @cfg, $line;
    }

    my $cf = {};
    $cf->{LOCATION} = $header->{LOCATION};
    $cf->{CHMOD}    = $header->{CHMOD};
    $cf->{CONTENT}  = check_and_fill_template( \@cfg, $substitutions );

    return ($cf);
}

sub _generic ( $template, $substitutions ) {

    return {
        LOCATION => $template->{LOCATION},
        CHMOD    => $template->{CHMOD},
        CONTENT  => check_and_fill_template( $template->{CONTENT}, $substitutions )
    };
}

##### frontend

sub gen_csync ($query) {

    print_table 'Generating csync cfg:', ' ', ': ';
    my $templates     = $query->('templates csync');
    my $scripts       = $query->('scripts csync');
    my $config        = $query->('config csync');
    my $nodes         = $query->('config csync nodes');
    my $substitutions = $query->('substitutions csync');
    my @cf            = ();

    if ( scalar keys $nodes->%* <= 1 ) {
        say 'skipping: not enough nodes in group';
        return;
    }

    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );

    push @cf, _gen_csync( $config, $templates->{'csync2.cfg'}, $substitutions );
    push @cf, _generic( $templates->{'csync2.init'}, $substitutions );
    push @cf, _generic( $templates->{'lsyncd.init'}, $substitutions );
    push @cf, _gen_lsync( $config, $templates->{'lsyncd.conf_header'}, $templates->{'lsyncd.conf_footer'}, $substitutions );

    say 'OK';
    return $filled_scripts, @cf;
}

1;
