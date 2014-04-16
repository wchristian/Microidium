package DW;

use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT SPACE );
use Math::Trig qw' deg2rad rad2deg ';
use SDLx::Sprite;
use Math::Vec qw(NewVec);

use Moo;

with 'FW';

__PACKAGE__->new->run if !caller;

1;

sub _build_client_state { { thrust => 0, turn_left => 0, turn_right => 0, zoom => 2 } }

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick   => 0,
        player => {
            x            => 0,
            y            => 0,
            x_speed      => 0,
            y_speed      => 0,
            turn_speed   => 5,
            rot          => 180,
            thrust_power => 1,
            max_speed    => 8,
            thrust_stall => 0.05,
        },
        computers => [
            map +{
                x            => $_ * 50,
                y            => 0,
                x_speed      => 0,
                y_speed      => 0,
                turn_speed   => ( rand() * 5 ) + 1,
                rot          => 180,
                thrust_power => rand() + 0.2,
                max_speed    => 8,
                thrust_stall => 0.05,
            },
            -5 .. 5
        ],
        ceiling => -600,
        floor   => 0,
        gravity => 0.15,
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

    my @p = ( $old_game_state->{player}, $old_game_state, $new_game_state->{player}, $new_game_state, $client_state );
    $self->apply_translation_forces( @p );
    $self->apply_rotation_forces( @p );

    my @old_computers = @{ $old_game_state->{computers} };
    my @new_computers = @{ $new_game_state->{computers} };
    for my $i ( 0 .. $#old_computers ) {
        my $input = $self->simple_ai_step( $old_computers[$i], $old_game_state->{player} );
        my @c = ( $old_computers[$i], $old_game_state, $new_computers[$i], $new_game_state, $input );
        $self->apply_translation_forces( @c );
        $self->apply_rotation_forces( @c );
    }

    return;
}

sub simple_ai_step {
    my ( $self, $computer, $player ) = @_;

    my @vec_to_player = NewVec( $computer->{x}, $computer->{y} )->Minus( [ $player->{x}, $player->{y} ] );
    my $dot_product   = NewVec( @vec_to_player )->Dot( [ 0, -1 ] );
    my $perpDot       = $vec_to_player[0] * -1 - $vec_to_player[1] * 0;
    my $angle_to_down = rad2deg atan2( $perpDot, $dot_product );
    my $comp_rot      = $computer->{rot};
    $comp_rot -= 360 if $comp_rot > 180;
    my $angle_to_player = $comp_rot - $angle_to_down;
    $angle_to_player -= 360 if $angle_to_player > 180;
    $angle_to_player += 360 if $angle_to_player < -180;

    my $turn_left  = $angle_to_player < 0;
    my $turn_right = $angle_to_player > 0;
    my $thrust     = abs( $angle_to_player ) < 60;

    return { turn_left => $turn_left, turn_right => $turn_right, thrust => $thrust };
}

sub apply_translation_forces {
    my ( $self, $old_player, $old_game_state, $new_player, $new_game_state, $client_state ) = @_;

    my $x_speed_delta = 0;
    my $y_speed_delta = 0;

    my $gravity = $old_game_state->{gravity};
    $gravity *= -1 if $old_player->{y} > $old_game_state->{floor};
    $y_speed_delta += $gravity;

    if ( $client_state->{thrust} ) {
        my $rad_rot      = deg2rad $old_player->{rot};
        my $thrust_power = $old_player->{thrust_power};
        $thrust_power = $old_player->{thrust_stall}
          if $old_player->{y} > $old_game_state->{floor}
          or $old_player->{y} < $old_game_state->{ceiling};
        $x_speed_delta += $thrust_power * sin $rad_rot;
        $y_speed_delta += $thrust_power * cos $rad_rot;
    }

    $new_player->{x_speed} = $old_player->{x_speed} + $x_speed_delta;
    $new_player->{y_speed} = $old_player->{y_speed} + $y_speed_delta;

    my $max_speed    = $old_player->{max_speed};
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
    my ( $self, $old_player, $old_game_state, $new_player, $new_game_state, $client_state ) = @_;
    return if !$client_state->{turn_left} and !$client_state->{turn_right};

    my $sign = $client_state->{turn_right} ? -1 : 1;
    my $turn_speed = $old_player->{turn_speed};
    $new_player->{rot} = $old_player->{rot} + $sign * $turn_speed;
    $new_player->{rot} += 360 if $new_player->{rot} < 0;
    $new_player->{rot} -= 360 if $new_player->{rot} > 360;
    return;
}

sub render_world {
    my ( $self, $world, $game_state ) = @_;
    my $player = $game_state->{player};

    if ( ( my $ceil_height = $world->h / 2 - $player->{y} + $game_state->{ceiling} ) >= 0 ) {
        $world->draw_rect( [ 0, 0, $world->w, $ceil_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $ceil_height ], [ $world->w, $ceil_height ], 0xff_ff_ff_ff, 0 );
    }

    if ( ( my $floor_height = $world->h / 2 - $player->{y} + $game_state->{floor} ) <= $world->h ) {
        $world->draw_rect( [ 0, $floor_height, $world->w, $world->h - $floor_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $floor_height ], [ $world->w, $floor_height ], 0xff_ff_ff_ff, 0 );
    }

    $world->draw_line(
        [ ( $world->w * $_ - $player->{x} ) % $world->w, 0, ],
        [ ( $world->w * $_ - $player->{x} ) % $world->w, $world->h ],
        0xff_ff_ff_44, 0
    ) for qw( 0.25 0.5 0.75 1 );

    $world->draw_line(
        [ 0, ( $world->h * $_ - $player->{y} ) % $world->h ],
        [ $world->w, ( $world->h * $_ - $player->{y} ) % $world->h ],
        0xff_ff_ff_44, 0
    ) for qw( 0.25 0.5 0.75 1 );

    for my $flier ( $player, @{ $game_state->{computers} } ) {

        my $sprite = SDLx::Sprite->new( image => "player.png" );
        $sprite->x( $flier->{x} - $player->{x} + $world->w / 2 - $sprite->{orig_surface}->w / 4 );
        $sprite->y( $flier->{y} - $player->{y} + $world->h / 2 - $sprite->{orig_surface}->h / 4 );
        $sprite->rotation( $flier->{rot} + 180 );
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
    }

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
