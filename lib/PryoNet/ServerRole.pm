package PryoNet::ServerRole;

# VERSION

use IO::Async::Loop;

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}

use Moo::Role;

has loop    => ( is => 'ro', default => sub { IO::Async::Loop->new } );
has clients => ( is => 'ro', default => sub { [] } );

sub listen {
    my ( $self, $tcp_port ) = @_;

    $self->loop->listen(
        service   => $tcp_port,
        socktype  => "stream",
        on_stream => sub {
            my ( $stream ) = @_;
            my $socket     = $stream->read_handle;
            my $peeraddr   = $socket->peerhost . ":" . $socket->peerport;
            print "$peeraddr joins\n";
            $stream->configure(
                on_read => sub {
                    my ( $stream, $buffref, $eof ) = @_;
                    if ( my $frame = $self->extract_frame( $buffref ) ) {
                        print "$frame\n";
                        $stream->write( $self->create_frame( $frame ) );
                    }
                    return 0;
                },
                on_closed => sub {
                    my ( $stream ) = @_;
                    @{ $self->clients } = grep { $_ != $stream } @{ $self->clients };
                    print "$peeraddr leaves\n";
                },
                autoflush => 1,
            );
            $self->loop->add( $stream );
            push @{ $self->clients }, $stream;
        },
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_listen_error  => sub { die "Cannot listen"; },
    );

    return;
}

sub write {
    my ( $self, $msg ) = @_;
    my $frame = $self->create_frame( $msg );
    $_->write( $frame ) for @{ $self->clients };
    return;
}

1;
