package PryoNet::SerializationRole;

use strictures;

# VERSION

use Sereal qw( encode_sereal decode_sereal );
use Scalar::Util 'blessed';
use Carp 'confess';

use Moo::Role;

sub create_frame {
    my ( $self, $v ) = @_;
    confess "only objects can be serialized" if !blessed $v;
    return pack 'N/a*', encode_sereal( $v );
}

sub extract_frame {
    my ( $self, $data ) = @_;
    my $len = length $$data;
    return if $len <= 4;

    my $size = 4 + unpack 'N1', substr $$data, 0, 4;
    return if $len < $size;

    my $frame = substr $$data, 0, $size, '';
    substr $frame, 0, 4, '';
    $frame = decode_sereal( $frame );
    return $frame;
}

1;
