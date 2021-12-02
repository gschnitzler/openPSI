#!/usr/bin/perl
use lib 'Libs';
use ModernStyle;
use Data::Dumper;

open( my $fh, '-|', 'md5sum -b /data/local_config/secrets/*' );
my @sum = <$fh>;
close $fh;

my $list = {};

foreach my $entry (@sum) {

	my ( $hash, $file ) = split( ' \*', $entry );
	chomp $file;
	$file =~ s/.*\///;

    if ( exists( $list->{$hash} ) ) {
        push $list->{$hash}->@*, $file;
    }
    else {
        $list->{$hash} = [$file];
    }
}

foreach my $hash (keys($list->%*)){

	delete $list->{$hash} if(scalar $list->{$hash}->@* == 1);
}


foreach my $hash (keys($list->%*)){

	say for ($list->{$hash}->@*);
	say '';
}


#	say Dumper $list;

