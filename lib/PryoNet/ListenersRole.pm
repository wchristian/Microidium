package PryoNet::ListenersRole;

# VERSION

use Moo::Role;

has listeners => ( is => 'ro', default => sub { { received => [] } } );

sub on_read {
    my ( $self, $connection, $stream, $buffref, $eof ) = @_;
    while ( my $frame = $self->extract_frame( $buffref ) ) {
        for my $listener ( @{ $self->listeners->{received} } ) {
            $listener->( $connection, $frame );
        }
    }
    return 0;
}

sub add_listener {
    my ( $self, $type, $listener ) = @_;
    push @{ $self->listeners->{$type} }, $listener;
    return;
}

1;
