package PryoNet::ListenersRole;

use strictures;

# VERSION

use Moo::Role;

has listeners => ( is => 'ro', default => sub { { received => [] } } );

sub on_read {
    my ( $self, $connection, $stream, $buffref, $eof ) = @_;
    while ( my $frame = $self->extract_frame( $buffref ) ) {
        $_->( $connection, $frame ) for @{ $self->listeners->{received} };
    }
    return 0;
}

sub add_listeners {
    my ( $self, %listeners ) = @_;
    push @{ $self->listeners->{$_} }, $listeners{$_} for keys %listeners;
    return;
}

1;
