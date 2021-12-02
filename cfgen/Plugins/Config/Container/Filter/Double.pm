package Plugins::Config::Container::Filter::Double;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(check_double);

sub check_double ( $known, $name, $conips ) {

    foreach my $key ( keys $conips->%* ) {
        my $ip = $conips->{$key};

        # took me minutes the 2nd time i looked at this:
        # first time an ip is encountered, a ip=>name pair is created.
        # the second time, the die statement is invoked, because the name stored does not match the current ones
        $known->{$ip} = $name unless ( exists( $known->{$ip} ) );
        die "ERROR: suffix $ip already in use by $known->{$ip}" if ( $known->{$ip} ne $name );
    }
    return;
}

1;
