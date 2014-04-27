package PryoNet::ClientRole;

# VERSION

use Sereal qw( encode_sereal decode_sereal );
use IO::Async::Loop;

{    # preload these to avoid frame drops
    use IO::Async::Resolver;
    use IO::Async::Internals::Connector;
    use IO::Async::Future;
}

use Moo::Role;

has loop => ( is => 'ro', default => sub { IO::Async::Loop->new } );
has tcp => ( is => 'rw' );

sub connect {
    my ( $self, $host, $tcp_port ) = @_;

    $self->loop->connect(
        host      => $host,
        service   => $tcp_port,
        socktype  => "stream",
        on_stream => sub {
            my ( $stream ) = @_;
            $stream->configure(
                on_read => sub {
                    my ( $self, $buffref, $eof ) = @_;
                    while ( $$buffref =~ s/^(.*)\n// ) {
                        my $got = decode_sereal( $1 );
                        print "got: $got\n";
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
    my $send = encode_sereal( $msg );
    $self->tcp->write( "$send\n" );
    return;
}

1;
