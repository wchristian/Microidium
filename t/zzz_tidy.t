use strictures 2;

use Test::InDistDir;
use Test::More;

use Test::ReportPerlTidy;    # from https://github.com/wchristian/Test-ReportPerlTidy

run();
done_testing;
exit;

sub run {
    Test::ReportPerlTidy::run( sub { shift =~ /^Makefile\.PL$|^Microidium-\d/ } );
    return;
}
