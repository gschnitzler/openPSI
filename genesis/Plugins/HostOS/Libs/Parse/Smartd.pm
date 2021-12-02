package Plugins::HostOS::Libs::Parse::Smartd;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_smartd);

#####################################################################

sub gen_smartd ($query) {

    print_table 'Generating smartd:', ' ', ': ';
    my $templates        = $query->('templates smartd');
    my $scripts          = $query->('scripts smartd');
    my $substitutions    = $query->('substitutions smartd');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
