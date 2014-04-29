package Microidium::ServerRole;

# VERSION

use PryoNet::Server;
use IO::Async::Timer::Periodic;
use Time::HiRes 'time';
use Clone 'clone';

use Moo::Role;

has game_state => ( is => 'rw',   builder => 1 );
has pryo       => ( is => 'lazy', builder => 1 );
has client_state => ( is => 'rw' );

sub _build_pryo { PryoNet::Server->new( client => shift ) }

sub run {
    my ( $self ) = @_;
    my $PORT     = 19366;
    my $pryo     = $self->pryo;
    $pryo->listen( $PORT );

    my $tick = 0;

    my $timer = IO::Async::Timer::Periodic->new(
        interval => 0.016,
        on_tick  => sub {
            $tick++;
            my $new_game_state = clone $self->game_state;
            $self->update_game_state( $new_game_state );
            $self->game_state( $new_game_state );
            $pryo->write( $new_game_state );
        },
    );

    $timer->start;
    $pryo->loop->add( $timer );
    $pryo->loop->run;
    return;
}

sub player_control {
    my ( $self, $actor ) = @_;
    return $self->client_state if $self->client_state;
    return $self->computer_ai( $actor, $self->game_state );
}

1;
