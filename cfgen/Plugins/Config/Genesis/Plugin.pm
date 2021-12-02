package Plugins::Config::Genesis::Plugin;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use IO::Templates::Read qw(read_templates);

our @EXPORT_OK = qw(import_hooks);

sub import_loader ( $debug, $query ) {

    my $paths       = $query->('paths');
    my $libs_dir    = $paths->{psi}->{LIBS};
    my $genesis_dir = $paths->{psi}->{GENESIS};

    my $distribution = {
        Libs    => read_templates( $debug, $libs_dir ),
        genesis => read_templates( $debug, $genesis_dir )
    };

    # remove the local config from genesis.pl
    for my $line ( $distribution->{genesis}->{'genesis.pl'}->{CONTENT}->@* ) {
        if ( $line =~ /^use\s+lib/ ) {
            $line =~ s/,[^,]+$/;/;
            last;
        }
    }

    return {
        state => {
            genesis => sub () {
                return dclone $distribution;
            }
        },
        scripts => {},
        macros  => {},
        cmds    => []
    };
}

sub import_hooks($self) {
    return {
        name    => 'Genesis',
        require => ['Paths'],
        loader  => \&import_loader,
        data    => { paths => 'state paths', }
    };
}

