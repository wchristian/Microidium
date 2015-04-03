package PryoNet::ClientRole;

use strictures;

# VERSION

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}

use IO::Async::Loop;
use PryoNet::FrameWorkMessage::RegisterTCP;
use PryoNet::FrameWorkMessage::RegisterUDP;
use IO::Async::Timer::Countdown;
use IO::Async::Timer::Periodic;
use IO::Async::Socket;
use Socket qw' inet_ntoa unpack_sockaddr_in ';

use Moo::Role;

has [qw( connect_timeout tcp_registered udp_registered udp_port udp )] => ( is => 'rw' );

sub connect {
    my ( $self, $timeout, $host, $tcp_port, $udp_port ) = @_;

    $self->connect_timeout( $timeout );
    $self->udp_port( $udp_port );

    $self->id( undef );

    $self->tcp_registered( 0 );
    $self->loop->connect(
        host             => $host,
        service          => $tcp_port,
        socktype         => "stream",
        on_stream        => $self->curry::on_accept,
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_connect_error => sub { die "Cannot connect - $_[0] failed $_[-1]\n"; },
    );

    my %timer = (
        delay     => $timeout,
        on_expire => sub { die "Connected, but timed out during TCP registration." if !$self->tcp_registered },
    );
    $self->loop->add( IO::Async::Timer::Countdown->new( %timer )->start );

    return if !$udp_port;

    $self->udp_registered( 0 );
    $self->loop->connect(
        host             => $host,
        service          => $udp_port,
        socktype         => "dgram",
        on_connected     => $self->curry::on_connect_udp,
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_connect_error => sub { die "Cannot connect - $_[0] failed $_[-1]\n"; },
    );

    return;
}

sub on_accept {
    my ( $self, $stream ) = @_;
    $_->() for @{ $self->listeners->{connected} };
    $stream->configure(
        on_read   => $self->curry::on_read,
        on_closed => $self->curry::on_closed,
        autoflush => 1,
    );
    $self->loop->add( $stream );
    $self->tcp( $stream );
    return;
}

sub on_connect_udp {
    my ( $self, $sock ) = @_;

    my $socket = IO::Async::Socket->new(
        handle        => $sock,
        on_recv       => $self->curry::on_recv_udp,
        on_recv_error => sub { die "Cannot recv - $_[1]\n" },
    );
    $self->loop->add( $socket );
    $self->udp( $socket );

    return;
}

sub register_udp {
    my ( $self ) = @_;

    my %timer = (
        delay     => $self->connect_timeout,
        on_expire => sub { die "Connected, but timed out during UDP registration." if !$self->udp_registered },
    );
    $self->loop->add( IO::Async::Timer::Countdown->new( %timer )->start );

    my $register_udp = PryoNet::FrameWorkMessage::RegisterUDP->new( connection_id => $self->id );
    my %repeater = ( interval => 0.1, on_tick => $self->curry::send_register_udp( $register_udp ) );
    $self->loop->add( IO::Async::Timer::Periodic->new( %repeater )->start );

    return;
}

sub send_register_udp {
    my ( $self, $register_udp, $timer ) = @_;
    if ( $self->udp_registered ) {
        $timer->stop;
        return;
    }
    $self->send_udp( $register_udp );
    return;
}

sub on_recv_udp {
    my ( $self, $sock, $dgram, $addr ) = @_;
    my $frame = $self->extract_frame( \$dgram );

    $_->( $self, $frame ) for @{ $self->listeners->{received} };

    return;
}

sub on_read {
    my ( $self, $stream, $buffref, $eof ) = @_;
    while ( my $frame = $self->extract_frame( $buffref ) ) {
        if ( !$self->tcp_registered ) {
            if ( $frame->isa( "PryoNet::FrameWorkMessage::RegisterTCP" ) ) {
                $self->id( $frame->connection_id );
                $self->tcp_registered( 1 );
                if ( $self->udp ) {
                    $self->register_udp;
                }
                else {
                    $self->connected( 1 );
                    $_->() for @{ $self->listeners->{connected} };
                }
            }
            next;
        }
        if ( $self->udp and !$self->udp_registered ) {
            if ( $frame->isa( "PryoNet::FrameWorkMessage::RegisterUDP" ) ) {
                $self->udp_registered( 1 );
                my $udp_handle = $self->udp->read_handle;
                my ( $local_port, $remote_host, $remote_port ) =
                  map { $udp_handle->$_ } qw( sockport peerhost peerport);
                $self->connected( 1 );
                $_->() for @{ $self->listeners->{connected} };
            }
            next;
        }
        next if !$self->connected;
        $_->( $self, $frame ) for @{ $self->listeners->{received} };
    }
    return 0;
}

sub on_closed {
    my ( $self ) = @_;
    $_->() for @{ $self->listeners->{disconnected} };
    return;
}

1;
