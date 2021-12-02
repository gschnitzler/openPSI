package Plugins::HostOS::Libs::Parse::Archive;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_archive);

#####################################################################

sub gen_archive ($query) {

    print_table 'Generating archive server:', ' ', ': ';
    my $templates        = $query->('templates archive');
    my $scripts          = $query->('scripts archive');
    my $substitutions    = $query->('substitutions archive');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );

    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
