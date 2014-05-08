package PryoNet::ConnectionRole;

use Moo::Role;

has tcp => ( is => 'rw' );
has id  => ( is => 'ro' );

sub send_tcp {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $self->tcp->write( $frame );
    return;
}

1;
