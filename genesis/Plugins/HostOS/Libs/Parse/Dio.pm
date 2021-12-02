package Plugins::HostOS::Libs::Parse::Dio;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_dio);

#####################################################################

sub gen_dio ($query) {

    print_table 'Generating dio:', ' ', ': ';
    my $templates        = $query->('templates dio');
    my $scripts          = $query->('scripts dio');
    my $substitutions    = $query->('substitutions dio');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
