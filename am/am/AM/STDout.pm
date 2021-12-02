package AM::STDout;

use ModernStyle;
use Exporter qw(import);

use PSI::Console qw(string_table);

our @EXPORT_OK = qw(write_stdout print_stdout);

#############################

sub _get_line(@args) {
    my $one = ( $args[0] ) ? shift @args : '';
    my $two = ( $args[0] ) ? shift @args : '';
    my $three = ( $args[0] ) ? join ' ', @args : '';
    return unless $one;
    return string_table( $one, "$two: ", $three );
}

sub _write_stdout ( $client, @args ) {
    my $line = _get_line(@args);
    $client->( 'WRITE', 'STDOUT', $line ) if $line;
    return;
}

sub _print_stdout ( @args ) {
    my $line = _get_line(@args);
    say $line if $line;
    return;
}

sub _print ( $handler, @args ) {
    if ( ref $args[0] ne 'ARRAY' ) {    # one msg
        $handler->(@args);
        return;
    }

    for my $msg (@args) {               # multiple msgs
        $handler->( $msg->@* );
    }
    return;
}

###########################################

sub write_stdout ( $client, @args ) {
    return _print( sub (@a) { return _write_stdout( $client, @a ) }, @args );
}

sub print_stdout (@args) {
    return _print( \&_print_stdout, @args );
}

1;
