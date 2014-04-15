package DW;

use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT SPACE );
use Math::Trig 'deg2rad';
use SDLx::Sprite;

use Moo;

with 'FW';

__PACKAGE__->new->run if !caller;

1;

sub _build_client_state { { thrust => 0, turn_left => 0, turn_right => 0 } }

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick   => 0,
        player => {
            x            => $self->w / 2,
            y            => $self->h / 2,
            x_speed      => 0,
            y_speed      => 0,
            turn_speed   => 5,
            rot          => 0,
            thrust_power => 1,
        }
    };
}

sub on_quit { shift->stop }

sub on_keydown {
    my ( $self, $event ) = @_;
    my $sym = $event->key_sym;
    $self->stop if $sym == SDLK_q;
    $self->client_state->{thrust}     = 1 if $sym == SDLK_UP;
    $self->client_state->{turn_left}  = 1 if $sym == SDLK_LEFT;
    $self->client_state->{turn_right} = 1 if $sym == SDLK_RIGHT;
    $self->client_state->{fire}       = 1 if $sym == SDLK_SPACE;
    return;
}

sub on_keyup {
    my ( $self, $event ) = @_;
    my $sym = $event->key_sym;
    $self->client_state->{thrust}     = 0 if $sym == SDLK_UP;
    $self->client_state->{turn_left}  = 0 if $sym == SDLK_LEFT;
    $self->client_state->{turn_right} = 0 if $sym == SDLK_RIGHT;
    $self->client_state->{fire}       = 0 if $sym == SDLK_SPACE;
    return;
}

sub update_game_state {
    my ( $self, $old_game_state, $new_game_state, $client_state ) = @_;
    $new_game_state->{tick}++;
    $self->apply_translation_forces( $old_game_state, $new_game_state, $client_state );
    $self->apply_rotation_forces( $old_game_state, $new_game_state, $client_state );
    return;
}

sub apply_translation_forces {
    my ( $self, $old_game_state, $new_game_state, $client_state ) = @_;

    my $old_player = $old_game_state->{player};
    my $new_player = $new_game_state->{player};

    my $x_speed_delta = 0;
    my $y_speed_delta = 0;

    my $gravity = 0.15;
    $gravity *= -1 if $old_player->{y} < 0;
    $y_speed_delta -= $gravity;

    if ( $client_state->{thrust} ) {
        my $rad_rot      = deg2rad $old_player->{rot};
        my $thrust_power = $old_player->{thrust_power};
        $thrust_power = 0.05 if $old_player->{y} < 0 or $old_player->{y} > $self->h;
        $x_speed_delta += $thrust_power * sin $rad_rot;
        $y_speed_delta += $thrust_power * cos $rad_rot;
    }

    $new_player->{x_speed} = $old_player->{x_speed} + $x_speed_delta;
    $new_player->{y_speed} = $old_player->{y_speed} + $y_speed_delta;

    my $max_speed    = 8;
    my $player_speed = ( $new_player->{x_speed}**2 + $new_player->{y_speed}**2 )**0.5;
    if ( $player_speed > $max_speed ) {
        my $mult = $max_speed / $player_speed;
        $new_player->{x_speed} *= $mult;
        $new_player->{y_speed} *= $mult;
    }

    $new_player->{x} = $old_player->{x} + $new_player->{x_speed};
    $new_player->{y} = $old_player->{y} + $new_player->{y_speed};

    return;
}

sub apply_rotation_forces {
    my ( $self, $old_game_state, $new_game_state, $client_state ) = @_;
    return if !$client_state->{turn_left} and !$client_state->{turn_right};

    my $sign       = $client_state->{turn_left} ? -1 : 1;
    my $turn_speed = $old_game_state->{player}{turn_speed};
    my $new_player = $new_game_state->{player};
    $new_player->{rot} = $old_game_state->{player}{rot} + $sign * $turn_speed;
    $new_player->{rot} += 360 if $new_player->{rot} < 0;
    $new_player->{rot} -= 360 if $new_player->{rot} > 360;
    return;
}

sub render_world {
    my ( $self, $world, $game_state ) = @_;
    my $player  = $game_state->{player};

    my $sprite = SDLx::Sprite->new( image => "player.png" );
    $sprite->x( $player->{x} - $sprite->{orig_surface}->w / 4 );
    $sprite->y( $player->{y} - $sprite->{orig_surface}->h / 4 );
    $sprite->rotation( $player->{rot} + 180 );
    $sprite->alpha( 0.5 );
    $sprite->clip(
        [
            $sprite->{orig_surface}->w / 4 + ( $sprite->surface->w - $sprite->{orig_surface}->w ) / 2,
            $sprite->{orig_surface}->h / 4 + ( $sprite->surface->h - $sprite->{orig_surface}->h ) / 2,
            $sprite->{orig_surface}->w / 2,
            $sprite->{orig_surface}->h / 2,
        ]
    );
    $sprite->draw( $world );

    return;
}

sub render_ui {
    my ( $self, $game_state ) = @_;
    $self->draw_gfx_text(
        [ 0, $self->h - 32 ],
        0xff_ff_ff_ff, join ' ',
        ( map $game_state->{player}{$_}, qw( x y rot ) ),
        ( $game_state->{player}->{x_speed}**2 + $game_state->{player}->{y_speed}**2 )**0.5
    );
    $self->draw_gfx_text( [ 0, $self->h - 24 ], 0xff_ff_ff_ff, $self->fps );
    $self->draw_gfx_text( [ 0, $self->h - 16 ], 0xff_ff_ff_ff, $self->frame );
    $self->draw_gfx_text( [ 0, $self->h - 8 ],  0xff_ff_ff_ff, $game_state->{tick} );
    return;
}
