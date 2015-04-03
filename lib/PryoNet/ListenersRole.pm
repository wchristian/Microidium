package PryoNet::ListenersRole;

use strictures;

# VERSION

use Moo::Role;

has listeners => ( is => 'ro', default => sub { { received => [] } } );

sub add_listeners {
    my ( $self, %listeners ) = @_;
    push @{ $self->listeners->{$_} }, $listeners{$_} for keys %listeners;
    return;
}

1;
