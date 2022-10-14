package Plugins::HostOS::Libs::Parse::Fail2Ban;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use IO::Templates::Parse qw(check_and_fill_template_tree);

our @EXPORT_OK = qw(gen_fail2ban);

##########################################################

sub gen_fail2ban ($query) {

    print_table 'Generating Fail2Ban:', ' ', ': ';
    my $templates        = $query->('templates fail2ban');
    my $substitutions    = $query->('substitutions fail2ban');
    my $filled_templates = check_and_fill_template_tree( $templates, $substitutions );
    say 'OK';
    return $filled_templates;
}

1;
