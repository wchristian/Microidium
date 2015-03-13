package PryoNet::ConnectionRole;

use strictures;

use Log::Contextual qw( :log :dlog  );

use Moo::Role;

has [qw( udp tcp id connected udp_remote_address udp_remote_address_octets )] => ( is => 'rw' );

sub send_tcp {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $self->tcp->write( $frame, on_write => $self->curry::on_write, on_flush => $self->curry::on_flush( $msg ) );
    return;
}

sub send_udp {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $self->udp->send( $frame, undef, $self->udp_remote_address_octets );
    return;
}

sub on_write {
    my ( $self, $stream, $len ) = @_;
    slog_trace $self->name . " wrote $len bytes";
    return;
}

sub on_flush {
    my ( $self, $obj ) = @_;
    slog_trace $self->name . " sent TCP: " . ref $obj;
    return;
}

sub name { "Connection " . shift->id }

1;
