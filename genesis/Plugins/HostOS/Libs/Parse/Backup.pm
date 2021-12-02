package Plugins::HostOS::Libs::Parse::Backup;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_backup);

#####################################################################

sub gen_backup ($query) {

    print_table 'Generating backup config:', ' ', ': ';
    my $templates        = $query->('templates backup');
    my $scripts          = $query->('scripts backup');
    my $substitutions    = $query->('substitutions backup');
    my $filled_scripts   = check_and_fill_template_tree( $scripts, $substitutions );
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_scripts, $filled_templates;
}

1;
