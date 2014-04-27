#!/usr/bin/perl

use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Stream;

my $loop = IO::Async::Loop->new;

{
    my $PORT     = 19366;
    my $listener = ChatListener->new;
    $loop->add( $listener );
    $listener->listen(
        service          => $PORT,
        socktype         => 'stream',
        on_resolve_error => sub { die "Cannot resolve - $_[0]\n"; },
        on_listen_error  => sub { die "Cannot listen\n"; },
    );
    $loop->run;
}

package ChatListener;
use base qw( IO::Async::Listener );
use Sereal qw( encode_sereal decode_sereal );

my @clients;

sub on_stream {
    my ( $self, $stream ) = @_;
    my $socket   = $stream->read_handle;                          # $socket is just an IO::Socket reference
    my $peeraddr = $socket->peerhost . ":" . $socket->peerport;
    print "$peeraddr joins\n";
    $_->write( "$peeraddr joins\n" ) for @clients;                # Inform the others
    $stream->configure(
        on_read => sub {
            my ( $self, $buffref, $eof ) = @_;
            while ( $$buffref =~ s/^(.*)\n// ) {                  # eat a line from the stream input
                my $got = decode_sereal( $1 );
                print "$got\n";

                #$_ == $self or
                $_->write( encode_sereal( $got ) . "\n" ) for @clients;  # Reflect it to all but the stream who wrote it
            }
            return 0;
        },
        on_closed => sub {
            my ( $self ) = @_;
            @clients = grep { $_ != $self } @clients;
            print "$peeraddr leaves\n";
            $_->write( "$peeraddr leaves\n" ) for @clients;              # Inform the others
        },
    );
    $loop->add( $stream );
    push @clients, $stream;
}
