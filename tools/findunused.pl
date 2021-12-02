#!/usr/bin/perl -w

# tool to find unused modules
# just execute in the top directory

use lib 'Libs';
use ModernStyle;

open( my $fh, '-|', 'grep -rn use | grep qw | grep -v findused ' );
my @used = <$fh>;
close $fh;

for my $line (@used) {

    chomp $line;

    $line =~ s/:use\s+/ /;
    $line =~ s/qw\s*\(\s*(.*)\s*\)\s*\;/$1/;
    $line =~ s/:\d+\s+/ /;

    my ( $package, $module, @functions ) = split( /\s+/, $line );

    next if ( $functions[0] eq 'import' );
    next if ( $package =~ /\#/ );

    next if ( $package =~ /:/ );

    # inefficient, but its 2am
    foreach my $fun (@functions) {

        #say $fun;
        #say $package;
        # grep does not like -
        $fun =~ s/^-+//;
        open( my $fhf, '-|', "cat $package | grep -v 'use ' | grep -v lib | grep '$fun'" );
        my $line = readline($fhf);
        close $fhf;

        unless ($line) {
            say "$package $module $fun";
        }
    }
}

