use strictures;

# this builds a portable zip with everything needed to run the game on windows
#
# first it builds a portable copy of a windows system perl by scanning a
# procmon log file and copying all files read by perl.exe in the capture
#
# then it zips up all the files, skipping the ones not needed to run the game

use 5.010;
use Text::CSV_XS 'csv';
use IO::All -binary, -utf8;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

run();

sub status { say scalar( localtime ) . ": " . sprintf( shift, @_ ) }

sub run {
    my $start = time;

    my $base_path = $ARGV[0] || "c:\\perl";
    $base_path .= "\\";
    my $base_path_q = quotemeta $base_path;
    my $target_base = $ARGV[1] || "perl";

    if ( !-d "perl" ) {
        status "building portable perl";
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

        status "copying %s files", scalar @files;
        for my $file ( @files ) {
            my $io   = io( $file )->file;
            my $path = $io->filepath;
            $path =~ s/^$base_path_q//i;
            my $target_dir = io->catdir( $target_base, $path );
            $target_dir->mkpath if !$target_dir->exists;
            my $target_file = io->catfile( $target_dir->pathname, $io->filename )->name;
            $io->copy( $target_file );
        }
    }

    my $target_file = "Microidium.zip";
    if ( !-f $target_file ) {
        status "building zip";

        my @local_files = map $_->name, io( "." )->All_Files;
        status "filtering local files";

        my @to_ignore = grep { $_ and $_ !~ /^#/ and $_ ne "/perl" } split "\n", io( ".gitignore" )->all;
        push @to_ignore, "generate_colors", map "/$_", qw(  .git  Changes  META
          README.PATCHING  client.bat  server.bat  cpanfile  dist.ini  scratch
          t  perlcritic.rc  ), io( $0 )->filename;
        $_ =~ s/^\//^/g  for @to_ignore;
        $_ =~ s/\./\\./g for @to_ignore;
        $_ =~ s/\*/.*/g  for @to_ignore;

        for my $ignore ( @to_ignore ) {
            @local_files = grep { $_ !~ /$ignore/ } @local_files;
        }

        my $localdir = io( "." )->absolute->filename;

        status "zipping %s files", scalar @local_files;
        my $zip = Archive::Zip->new;
        $zip->addFile( $_, io->catfile( $localdir, $_ )->name, 9 ) for @local_files;
        $zip->writeToFileNamed( $target_file );
    }

    status "done";

    status "time taken: %s seconds", time - $start;

    return;
}
