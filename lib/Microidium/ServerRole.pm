package Microidium::ServerRole;

use strictures;

# VERSION

use PryoNet::Server;
use IO::Async::Timer::Periodic;
use Time::HiRes 'time';
use Clone 'clone';

use Moo::Role;

has game_state => ( is => 'rw',   builder => 1 );
has pryo       => ( is => 'lazy', builder => 1 );

sub _build_pryo { PryoNet::Server->new( client => shift ) }

sub run {
    my ( $self ) = @_;
    my $PORT     = 19366;
    my $pryo     = $self->pryo;
    $pryo->bind( $PORT );
    $pryo->add_listeners(
        connected => sub {
            my ( $connection ) = @_;
            my $players = $self->game_state->{players};
            $players->{ $connection->id } = { id => $connection->id, actor => undef, client_state => undef };
            printf "player connected %s ( %s total )\n", $connection->id, scalar values %{$players};
            $connection->send_tcp( { network_player_id => $connection->id } );
            return;
        },
        disconnected => sub {
            my ( $connection ) = @_;
            my $players = $self->game_state->{players};
            delete $players->{ $connection->id };
            printf "player disconnected %s ( %s total )\n", $connection->id, scalar values %{$players};
            return;
        },
        received => sub {
            my ( $connection, $frame ) = @_;
            my $player = $self->game_state->{players}{ $connection->id };
            return if !$player;
            $player->{client_state} = $frame;
            return;
        },
    );

    my $tick = 0;

    my $timer = IO::Async::Timer::Periodic->new(
        interval => 0.016,
        on_tick  => sub {
            $tick++;
            my $new_game_state = clone $self->game_state;
            $self->update_game_state( $new_game_state );
            $self->game_state( $new_game_state );
            $pryo->send_to_all_tcp( $new_game_state );
        },
    );

    $timer->start;
    $pryo->loop->add( $timer );
    $pryo->loop->run;
    return;
}

sub player_control {
    my ( $self, $actor ) = @_;
    my $player = $self->game_state->{players}{ $actor->{player_id} };
    my $player_state = $player ? $player->{client_state} : undef;
    return $player_state if $player_state;
    return $self->computer_ai( $actor, $self->game_state );
}

1;
