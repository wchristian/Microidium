use strictures;

# this builds a portable copy of a windows system perl by scanning a
# procmon log file and copying all files read by perl.exe in the capture

use 5.010;
use Text::CSV_XS 'csv';
use IO::All -binary, -utf8;

run();

sub run {
    my $base_path = $ARGV[0] || "c:\\perl";
    $base_path .= "\\";
    my $base_path_q = quotemeta $base_path;
    my $target_base = $ARGV[1] || "perl";

    my @log = do {
        my $data = io( "Logfile.CSV" )->all;
        $data =~ s/^.*?\n//;
        @{ csv in => \$data };
    };
    for my $filter (
        sub { $_->[1] eq "perl.exe" },         #
        sub { $_->[4] eq "CreateFile" },
        sub { $_->[7] eq "SUCCESS" },
        sub { $_->[6] =~ /^$base_path_q/i },
        sub { $_->[6] !~ /\.bs$/ },
        sub { -f $_->[6] },
      )
    {
        @log = grep $filter->( $_ ), @log;
    }

    my %files = map { $_->[6] => 1 } @log;
    my @files = sort keys %files;

    for my $file ( @files ) {
        say $file;
        my $io   = io( $file )->file;
        my $path = $io->filepath;
        $path =~ s/^$base_path_q//i;
        my $target_dir = io->catdir( $target_base, $path );
        $target_dir->mkpath if !$target_dir->exists;
        my $target_file = io->catfile( $target_dir->pathname, $io->filename )->name;
        $io->copy( $target_file );
    }

    return;
}
