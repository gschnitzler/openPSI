#!/usr/bin/perl
use lib '../Libs';
use ModernStyle;
use Data::Dumper;

my $secret_path = '/data/local_config/secrets';

sub _check_file($file) {
    open( my $fh, '-|', "openssl x509 -enddate -noout -in $secret_path/$file 2>/dev/null" );
    my $answer = readline $fh;
    close $fh;

    if ($answer){
        chomp $answer;
        $answer =~ s/notAfter=//;
        return $answer;
    }
    return;
}

sub _read_secrets(){
    open( my $fh, '-|', "ls $secret_path" );
    my @answer = <$fh>;
    close $fh;

    chomp for (@answer);
    return @answer;
}

for my $fp (_read_secrets){

    my $ssl_exp = _check_file($fp);
    say "\[$ssl_exp\] $fp" if ($ssl_exp);
}

exit;
