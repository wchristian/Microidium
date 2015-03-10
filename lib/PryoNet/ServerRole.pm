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

use Moo::Role;

has connections        => ( is => 'ro', default => sub { [] } );
has last_connection_id => ( is => 'rw', default => sub { 0 } );

sub bind {
    my ( $self, $tcp_port ) = @_;
    $self->loop->listen(
        service          => $tcp_port,
        socktype         => "stream",
        on_stream        => $self->curry::on_accept,
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_listen_error  => sub { die "Cannot listen"; },
    );
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
    push @{ $self->connections }, $connection;
    $_->( $connection ) for @{ $self->listeners->{connected} };
    return;
}

sub send_to_all_tcp {
    my ( $self, $msg ) = @_;
    $_->send_tcp( $msg ) for @{ $self->connections };
    return;
}

sub next_connection_id { ++shift->{last_connection_id} }

1;
