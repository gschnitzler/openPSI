package Plugins::HostOS::Libs::Parse::Ssmtp;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_ssmtp);

##########################################################

sub gen_ssmtp ($query) {

    print_table 'Generating ssmtp:', ' ', ': ';
    my $templates        = $query->('templates ssmtp');
    my $substitutions    = $query->('substitutions ssmtp');
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_templates;
}

1;
