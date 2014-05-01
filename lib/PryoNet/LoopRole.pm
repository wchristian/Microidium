package PryoNet::LoopRole;

# VERSION

use Moo::Role;

has loop => ( is => 'ro', default => sub { IO::Async::Loop->new } );

1;
