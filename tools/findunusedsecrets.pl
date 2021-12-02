#!/usr/bin/perl -w

# tool to find unused secrets
# just execute in the top directory

# keep in mind that secrets might be used outside of SECRETS: lines
# and just because a secrets not used does not mean its there for no reason...
# ...so even though the information might make little sense, it doesn't mean you shoulnt be able to use it...

use lib 'Libs';
use ModernStyle;
use PSI::Parse::Dir qw(get_directory_list);
use Data::Dumper;

open( my $fh, '-|', 'find . -type f | grep cfgen$ | xargs cat | grep SECRETS: | sed -e \'s/.*SECRETS://\' | sed -e "s/[,\' }]//g" | sort | uniq' );
my @used = <$fh>;
close $fh;

chomp for @used;

my %used_secrets = map { $_, 1 } @used;
my $secrets = get_directory_list('/data/local_config/secrets');

for my $k (sort keys $secrets->%*) {

    say $k unless exists $used_secrets{$k};
}

