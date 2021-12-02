# This is basically Modern::Perl with added experimental postderef and subroutine signatures
package DIO::ModernStyle;

use 5.014;
use strict;
use warnings;
use mro     ();
use feature ();
use experimental;

sub import {

    my ($class) = @_;
    strict->import;
    warnings->import;
    feature->import( ':5.20', 'signatures' );
    experimental->import('postderef');
    warnings->unimport('experimental::signatures');
    mro::set_mro( scalar caller(), 'c3' );
    return;
}

sub unimport {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    warnings->unimport;
    strict->unimport;
    feature->unimport;
    experimental->unimport;
    return;
}

1;
