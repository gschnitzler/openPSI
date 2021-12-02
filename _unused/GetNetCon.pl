#!/usr/bin/perl -w

use ModernStyle;


use Exporter qw(import);
use Data::Dumper;

# requires root
die "ERROR: not root" unless ( getpwuid($<) eq 'root' );

open( my $fh, '-|', 'lsof -iTCP -n' ) or die $!;
my @lsof = <$fh>;
close $fh;

my $struct = [];
foreach my $line (@lsof) {

    chomp($line);

    if ( $line =~ m/^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/ ) {

        my $i = {
            command    => $1,
            pid        => $2,
            user       => $3,
            connection => $9,
            state      => $10

        };

        $i->{state} =~ s/\((.*)\)/$1/;

        next unless ($i->{state} eq "ESTABLISHED");

        # unneeded info
        delete $i->{state};
        delete $i->{user};
        
        ($i->{lip}, $i->{lpo}, $i->{rip}, $i->{rpo}) = $i->{connection} =~ m/([\d.]+):([\d]+)->([\d.]+):([\d]+)/;
        delete $i->{connection};

        push $struct->@*, $i;
    }

}

# security-wise, it would be better to sanitize the lsof output in genesis
# however, until there is a proper sensor handler, we just eval the output
say Dumper $struct;


