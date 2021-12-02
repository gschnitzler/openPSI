package Plugins::HostOS::Libs::Parse::Syslog;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use IO::Templates::Parse qw(check_and_fill_template);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_open);

our @EXPORT_OK = qw(gen_syslog);

##########################################################

sub _gen_casymlink ( $cert, $capath ) {

    die 'ERROR: no cacert configured'   unless $cert;
    die 'ERROR: no cacert.pem location' unless $capath;

    my $cfpath = $capath;
    $cfpath =~ s/\/[^\/]+$//;

    # syslog requires symlinks for its ca cert... whatever, lets comply
    my ( $hash, @rest ) = run_open "cat << \"EOF\" | openssl x509 -noout -hash\n$cert\nEOF";
    die 'ERROR: openssl did not provide a return value' unless $hash;

    return {
        LOCATION => "$cfpath/$hash.0",
        SYMLINK  => "$capath",
        CHMOD    => '777',
        CONTENT  => [],
    };
}

sub _gen_syslogconf ( $p ) {

    my $cf                  = $p->{syslog_conf};
    my $capath              = $p->{cacert_location};
    my $certpath            = $p->{servercert_location};
    my $keypath             = $p->{serverkey_location};
    my $substitutions       = $p->{substitutions};
    my $port                = $p->{syslog_port};
    my $monitor_destination = $p->{monitor_config};

    die 'ERROR: no syslog port configured' unless $port;
    die 'ERROR: no server cert location'   unless $certpath;
    die 'ERROR: no server key location'    unless $keypath;
    $capath =~ s/\/[^\/]+$//;

    $cf->{CONTENT} = check_and_fill_template( $cf->{CONTENT}, $substitutions );

    # add rules for remote logging
    if ($monitor_destination) {
        push(
            $cf->{CONTENT}->@*,

            #
            'destination d_host_tls {',
            "syslog(\"$monitor_destination\"",
            'transport("tls")',
            "port($port)",
            'tls(',
            "ca-dir(\"$capath\")",
            "key-file(\"$keypath\")",
            "cert-file(\"$certpath\")",
            ')',

            # disk based buffering is available starting with syslog-ng 3.8.1, while gentoo is sticking to 3.7.3 with no plans to upgrade anytime soon.
            # the elk container uses 3.9 from source, but it seems to be a bad idea to put that into the base image
            # so meanwhile, lets use memory buffering via log-fifo-size
            #                "disk-buffer(",
            #                    "mem-buf-size(100000)",
            #                    "disk-buf-size(20971520)",
            #                    "reliable(yes)",
            #                    "dir(\"/var/lib/syslog-ng/buffer\")",
            #                ")",
            'log-fifo-size(100000)',
            ');',
            '};',
            'log { source(src); rewrite(r_source); destination(d_host_tls); flags(flow-control); };',
            'log { source(kernsrc); rewrite(r_source); destination(d_host_tls); flags(flow-control); };',
        );
    }

    return $cf;
}

sub _do_subs ( $cf, $substitutions ) {

    $cf->{CONTENT} = check_and_fill_template( $cf->{CONTENT}, $substitutions );
    return $cf;
}

##### frontend

sub gen_syslog ($query) {

    print_table 'Generating syslog Config:', ' ', ': ';
    my $templates     = $query->('templates syslog');
    my $substitutions = $query->('substitutions syslog');
    my $config        = $query->('config syslog');
    my @cfg           = ();

    push @cfg, _gen_casymlink( $config->{CACERT}, $templates->{'cacert.pem'}->{LOCATION} );
    push @cfg,
      _gen_syslogconf(
        {
            syslog_conf         => $templates->{'syslog-ng.conf'},
            cacert_location     => $templates->{'cacert.pem'}->{LOCATION},
            servercert_location => $templates->{'server.cert'}->{LOCATION},
            serverkey_location  => $templates->{'server.key'}->{LOCATION},
            substitutions       => $substitutions,
            syslog_port         => $config->{SYSLOGPORT},
            monitor_config      => $config->{MONITOR}
        }
      );
    push @cfg, _do_subs( $templates->{'cacert.pem'},  $substitutions );
    push @cfg, _do_subs( $templates->{'server.cert'}, $substitutions );
    push @cfg, _do_subs( $templates->{'server.key'},  $substitutions );

    say 'OK';
    return @cfg;
}
