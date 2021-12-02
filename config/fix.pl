#!/usr/bin/perl -w
#
#
use lib '/data/psi/Libs';
use ModernStyle;
use Data::Dumper;
use Cwd;
use File::Find;
use PSI::Parse::File qw(read_file);

sub _read ( $file, $path ) {

    return if ( !-f $file || $file !~ m/\.pm$/x );
    my $content = read_file($file);
    return if ( scalar $content->@* == 0 );
    return { CONTENT => $content, FILE => join('/', cwd, $file) };
}

my $path = $ARGV[0];
die "ERROR: not a path" if  ( ! $path || ! -e $path || ! -d $path);

my @files = ();
$File::Find::dont_use_nlink=1; # cifs does not support nlink
find( sub { push @files, _read( $_, $path ) }, $path );


foreach my $file (@files){

	my $file_path = $file->{FILE};
	my $content = $file->{CONTENT};

	my $counter = 0;
	foreach my $line ($content->@*){

		while  ($line =~ /(=.)/g){
			my $item = $1;

			$counter++ if $item !~ /=>/;
			

		}
	}

	say "$file_path: $counter";
	#say Dumper $content;


}

