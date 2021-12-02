#!/usr/bin/perl

use ModernStyle;
use Tie::File;
use Data::Dumper;

# print to stdout before newline
$|++;

# this parser was designed to quickly apply a (decreasing) series of expressions to a limited amount of very long lines in a file on disk
# it was not designed to handle huge amounts of lines (millions).

my $it      = 0;
my $changes = {};
my $regex   = {
    create => qr/^CREATE\ DATABASE.*/x,
    use    => qr/^USE\ .*/x,
    define => qr/DEFINER/x
};

sub say {
    print @_, "\n";
}

sub _counter {
    my $it = shift;
    $it++;
    if ( $it == 500 ) {
        print ".";
        $it = 0;
    }
    return $it;
}

sub _create {
    my $line = shift;
    if ( $line =~ $regex->{create} ) {
        _unregister("create");
        push @{ $changes->{create}->{before} }, $line;
        return (
            $regex->{create},
            sub {
                push @{ $changes->{create}->{after} }, @_;
            }
        );
    }
    return 0;
}

sub _use {
    my $line = shift;
    if ( $line =~ $regex->{use} ) {
        _unregister("use");
        push @{ $changes->{use}->{before} }, $line;
        return (
            $regex->{use},
            sub {
                push @{ $changes->{use}->{after} }, @_;
            }
        );
    }
    return 0;
}

sub _define {
    my $line = shift;
    if ( $line =~ $regex->{define} ) {
        push @{ $changes->{define}->{before} }, $line;
        return (
            qr/DEFINER=\`\w.*\`@\`[^\`]+\`/,
            sub {
                push @{ $changes->{define}->{after} }, @_;
            }
        );
    }
    return 0;
}

sub _help {
    say "usage: ./cleandb.pl <file>";
    say "takes a plain text sql <file> and does the following in place:";
    say "strips USE";
    say "strips CREATE";
    say "removes DEFINER user";
    exit 0;
}

my $dispatch = {
    create => \&_create,
    use    => \&_use,
    define => \&_define,
};

# to speed up parsing, handler can unregister themselfs. (some statements only occur once)
sub _unregister {
    my $key = shift;
    return delete $dispatch->{$key} if exists $dispatch->{$key};
    return;
}

#########################################

_help unless scalar @ARGV == 1;

my $file_name = shift @ARGV;
my @file      = ();

die "file '$file_name' does not exist" unless -e $file_name;

print "opening $file_name: ";
tie @file, 'Tie::File', $file_name, memory => 200_000_000 or die "cant open $file_name RW";
( tied @file )->defer;
say "OK";

print "parsing $file_name: ";

for my $line (@file) {

    # tie fiddles with $|, so the indicator is useless
    #$it=_counter($it);

    for my $key ( keys %{$dispatch} ) {

        my ( $regex, $update_changes ) = $dispatch->{$key}->($line);
        if ($regex) {
            $line =~ s/$regex//;
            $update_changes->($line);
        }
    }
}

say "OK";

( tied @file )->flush;
untie @file;

say "FINISHED, changes made:";

for my $key ( keys %{$changes} ) {

    my $entry = $changes->{$key};
    say $key, ":";
    say Dumper $entry;
}

