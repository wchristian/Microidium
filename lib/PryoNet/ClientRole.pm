package PryoNet::ClientRole;

# VERSION

use IO::Async::Loop;

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}

use Moo::Role;

has loop => ( is => 'ro', default => sub { IO::Async::Loop->new } );
has tcp => ( is => 'rw' );
has client => ( is => 'ro', required => 1 );

sub connect {
    my ( $self, $host, $tcp_port ) = @_;

    my $client = $self->client;

    $self->loop->connect(
        host      => $host,
        service   => $tcp_port,
        socktype  => "stream",
        on_stream => sub {
            my ( $stream ) = @_;
            $stream->configure(
                on_read => sub {
                    my ( $stream, $buffref, $eof ) = @_;
                    while ( my $frame = $self->extract_frame( $buffref ) ) {
                        $client->log( "got: " . ( ref $frame ? ( $frame->{tick} || "input" ) : $frame ) );
                        if ( ref $frame and $frame->{tick} ) {
                            $client->last_network_state( $frame );
                        }
                    }
                    return 0;
                },
                autoflush => 1,
            );
            $self->loop->add( $stream );
            $self->tcp( $stream );
            return;
        },
        on_resolve_error => sub { die "Cannot resolve - $_[0]"; },
        on_connect_error => sub { die "Cannot connect"; },
    );

    return;
}

sub write {
    my ( $self, $msg ) = @_;
    $self->tcp->write( $self->create_frame( $msg ) );
    return;
}

1;
