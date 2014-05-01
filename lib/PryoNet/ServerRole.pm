package PryoNet::ServerRole;

# VERSION

use IO::Async::Loop;

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}
use curry;
use PryoNet::Connection;

use Moo::Role;

has connections => ( is => 'ro', default => sub { [] } );

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
    my $socket   = $stream->read_handle;
    my $peeraddr = $socket->peerhost . ":" . $socket->peerport;
    print "$peeraddr joins\n";
    my $connection = PryoNet::Connection->new( tcp => $stream );
    $stream->configure(
        on_read   => $self->curry::on_read( $connection ),
        on_closed => sub {
            my ( $stream ) = @_;
            @{ $self->connections } = grep { $_ != $stream } @{ $self->connections };
            print "$peeraddr leaves\n";
        },
        autoflush => 1,
    );
    $self->loop->add( $stream );
    push @{ $self->connections }, $connection;
    return;
}

sub send_to_all_tcp {
    my ( $self, $msg ) = @_;
    $_->send_tcp( $msg ) for @{ $self->connections };
    return;
}

1;
