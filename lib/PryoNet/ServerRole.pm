package PryoNet::ServerRole;

use strictures;

# VERSION

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}

use IO::Async::Loop;
use curry;
use PryoNet::Connection;
use PryoNet::FrameWorkMessage::RegisterTCP;
use PryoNet::FrameWorkMessage::RegisterUDP;
use IO::Async::Socket;
use Socket qw' inet_ntoa unpack_sockaddr_in ';

use Moo::Role;

has connections         => ( is => 'ro', default => sub { [] } );
has pending_connections => ( is => 'ro', default => sub { {} } );
has last_connection_id  => ( is => 'rw', default => sub { 0 } );
has udp                 => ( is => 'rw' );

sub bind {
    my ( $self, $tcp_port ) = @_;
    $self->loop->listen(
        service          => $tcp_port,
        socktype         => "stream",
        on_stream        => $self->curry::on_accept,
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_listen_error  => sub { die "Cannot listen"; },
    );
    my $udp = IO::Async::Socket->new(
        handle  => IO::Socket::INET->new( Proto => "udp", LocalPort => $tcp_port ),
        on_recv => $self->curry::on_recv_udp,
        on_recv_error => sub { die "Cannot recv - $_[1]\n" },
    );
    $self->loop->add( $udp );
    $self->udp( $udp );
    return;
}

sub on_recv_udp {
    my ( $self, $sock, $dgram, $addr ) = @_;
    my ( $port, $ip_address ) = unpack_sockaddr_in $addr;
    my $ip_string    = inet_ntoa $ip_address;
    my $from_address = "$ip_string:$port";
    my $frame = $self->extract_frame( \$dgram );
    if ( $frame->isa( "PryoNet::FrameWorkMessage::RegisterUDP" ) ) {
        my $from_connection_id = $frame->connection_id;
        my $connection = delete $self->pending_connections->{$from_connection_id};
        return if !$connection or $connection->udp_remote_address;

        $connection->udp_remote_address_octets( $addr );
        $connection->udp_remote_address( $from_address );
        push @{ $self->connections }, $connection;
        $connection->send_tcp( PryoNet::FrameWorkMessage::RegisterUDP->new );
        $_->( $connection ) for @{ $self->listeners->{connected} };
        return;
    }
    return;
}

sub on_accept {
    my ( $self, $stream ) = @_;
    my $connection = PryoNet::Connection->new( tcp => $stream, id => $self->next_connection_id );
    $stream->configure(
        on_read   => $self->curry::on_read( $connection ),
        on_closed => sub {
            my ( $stream ) = @_;
            @{ $self->connections } = grep { $_ != $connection } @{ $self->connections };
            $_->( $connection ) for @{ $self->listeners->{disconnected} };
            return;
        },
        autoflush => 1,
    );
    $self->loop->add( $stream );

    if ( $self->udp ) {
        $connection->udp( $self->udp );
        $self->pending_connections->{ $connection->id } = $connection;
    }
    else {
        push @{ $self->connections }, $connection;
    }

    $connection->send_tcp( PryoNet::FrameWorkMessage::RegisterTCP->new( connection_id => $connection->id ) );

    return if $self->udp;

    $_->( $connection ) for @{ $self->listeners->{connected} };

    return;
}

sub on_read {
    my ( $self, $connection, $stream, $buffref, $eof ) = @_;
    while ( my $frame = $self->extract_frame( $buffref ) ) {
        $_->( $connection, $frame ) for @{ $self->listeners->{received} };
    }
    return 0;
}

sub send_to_all_tcp {
    my ( $self, $msg ) = @_;
    $_->send_tcp( $msg ) for @{ $self->connections };
    return;
}

sub send_to_all_udp {
    my ( $self, $msg ) = @_;
    $_->send_udp( $msg ) for @{ $self->connections };
    return;
}

sub next_connection_id { ++shift->{last_connection_id} }

1;
