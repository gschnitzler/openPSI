package Plugins::HostOS::Libs::Parse::Prometheus;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_prometheus);

#####################################################################

sub gen_prometheus ($query) {

    print_table 'Generating prometheus:', ' ', ': ';
    my $templates        = $query->('templates prometheus');
    my $scripts          = $query->('scripts prometheus');
    my $substitutions    = $query->('substitutions prometheus');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
