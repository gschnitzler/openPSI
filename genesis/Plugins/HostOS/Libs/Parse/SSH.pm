package Plugins::HostOS::Libs::Parse::SSH;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_ssh);

###############################################################

sub gen_ssh ($query) {

    print_table 'Generating SSH:', ' ', ': ';
    my $templates        = $query->('templates ssh');
    my $scripts          = $query->('scripts ssh');
    my $substitutions    = $query->('substitutions ssh');
    my $host_keys        = $query->('config ssh');
    my @cf               = ();
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );

    foreach my $hostkey_name ( keys $host_keys->%* ) {

        push(
            @cf,
            {
                LOCATION => $host_keys->{$hostkey_name}->{PUBPATH},
                CONTENT  => [ split( /\n/, $host_keys->{$hostkey_name}->{PUB} ) ],
                CHMOD    => '644',
            },
            {
                LOCATION => $host_keys->{$hostkey_name}->{PRIVPATH},
                CONTENT  => [ split( /\n/, $host_keys->{$hostkey_name}->{PRIV} ) ],
                CHMOD    => '600',
            }
        );
    }

    say 'OK';
    return $filled_templates, $filled_scripts, @cf;
}

1;
