#!/usr/bin/perl

use lib '/data/psi/Libs', '/data/psi/cfgen', '.';
use ModernStyle;
use Data::Dumper;
use Lib::Templates::Read qw(read_templates);
use Lib::Templates::Meta::Build qw(build_meta);
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Terse     = 1;
$Data::Dumper::Quotekeys = 0;

# usage: run it on a dir with a meta file
my $templates = read_templates(1, $ARGV[0]);
say Dumper $templates;

#usage: give a dir as argument, and > it to dir/.cfmeta
## edit the first argument to build_meta, if you need UID/GID/CHMOD
#my $meta = build_meta({ CHMOD => ''}, $ARGV[0]);
#say Dumper $meta;

