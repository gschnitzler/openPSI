#!/usr/bin/perl

# usage: 
# install Perl::Critic via cpan
# put the .perlcriticrc in place
# find . | grep '\.pm' | grep -v '\./config' | xargs ./tools/critic.pl
# 
use lib 'Libs';
use Perl::Critic;
use ModernStyle;


$|++;

foreach my $file (@ARGV) {

    say "File: $file";
    my $critic     = Perl::Critic->new(-severity => 1);
    my @violations = $critic->critique($file);
    print @violations;

}

