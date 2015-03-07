package Microidium::Helpers;

use strictures;

# VERSION

use Sub::Exporter::Simple 'dfile';

use File::ShareDir ':ALL';

sub dfile ($) {
    my ( $file ) = @_;
    my $dist = ( caller )[0];
    $dist =~ s/::/-/;
    my $path = eval { dist_file( $dist, $file ) };
    $path ||= "share/$file";
    return $path;
}

1;
