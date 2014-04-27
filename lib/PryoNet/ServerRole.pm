package PryoNet::ServerRole;

# VERSION

use Sereal qw( encode_sereal decode_sereal );
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
            my $socket     = $stream->read_handle;                          # $socket is just an IO::Socket reference
            my $peeraddr   = $socket->peerhost . ":" . $socket->peerport;
            print "$peeraddr joins\n";
            $stream->configure(
                on_read => sub {
                    my ( $stream, $buffref, $eof ) = @_;
                    while ( $$buffref =~ s/^(.*)\n// ) {                    # eat a line from the stream input
                        my $got = decode_sereal( $1 );
                        print "$got\n";
                        $stream->write( encode_sereal( $got ) . "\n" );
                    }
                    return 0;
                },
                on_closed => sub {
                    my ( $stream ) = @_;
                    @{ $self->clients } = grep { $_ != $stream } @{ $self->clients };
                    print "$peeraddr leaves\n";
                },
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
    my $send = encode_sereal( $msg );
    $_->write( "$send\n" ) for @{ $self->clients };
    return;
}

1;
