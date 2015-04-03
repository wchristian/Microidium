package PryoNet::ConnectionRole;

use strictures;

use Moo::Role;

has [qw( udp tcp id connected udp_remote_address udp_remote_address_octets )] => ( is => 'rw' );

sub send_tcp {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $self->tcp->write( $frame );
    return;
}

sub send_udp {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $self->udp->send( $frame, undef, $self->udp_remote_address_octets );
    return;
}

1;
