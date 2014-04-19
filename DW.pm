package DW;

use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d );
use Math::Trig qw' deg2rad rad2deg ';
use SDLx::Sprite;
use Math::Vec qw(NewVec);
use List::Util qw( first min );
use Carp::Always;

use Moo;

has player_sprite => ( is => 'ro', default => sub { SDLx::Sprite->new( image => "player.png" ) } );
has bullet_sprite => ( is => 'ro', default => sub { SDLx::Sprite->new( image => "bullet.png" ) } );
with 'FW';

__PACKAGE__->new->run if !caller;

1;

sub _build_client_state { { fire => 0, thrust => 0, turn_left => 0, turn_right => 0, zoom => 1 } }

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick           => 0,
        last_input     => 0,
        player         => undef,
        actors         => [],
        player_was_hit => 0,
        bullets        => [],
        ceiling        => -1800,
        floor          => 0,
        gravity        => 0.15,
    };
}

sub on_quit { shift->stop }

sub on_keydown {
    my ( $self, $event ) = @_;
    $self->game_state->{last_input} = time;
    my $sym = $event->key_sym;
    $self->stop if $sym == SDLK_q;
    $self->client_state->{thrust}     = 1 if $sym == SDLK_UP;
    $self->client_state->{turn_left}  = 1 if $sym == SDLK_LEFT;
    $self->client_state->{turn_right} = 1 if $sym == SDLK_RIGHT;
    $self->client_state->{fire}       = 1 if $sym == SDLK_d;
    return;
}

sub on_keyup {
    my ( $self, $event ) = @_;
    my $sym = $event->key_sym;
    $self->client_state->{thrust}     = 0 if $sym == SDLK_UP;
    $self->client_state->{turn_left}  = 0 if $sym == SDLK_LEFT;
    $self->client_state->{turn_right} = 0 if $sym == SDLK_RIGHT;
    $self->client_state->{fire}       = 0 if $sym == SDLK_d;
    return;
}

sub update_game_state {
    my ( $self, $old_game_state, $new_game_state, $client_state ) = @_;
    $new_game_state->{tick}++;

    my @old_bullets = @{ $old_game_state->{bullets} };
    my @new_bullets = @{ $new_game_state->{bullets} };
    for my $i ( 0 .. $#old_bullets ) {
        my @c = ( $old_bullets[$i], $old_game_state, $new_bullets[$i], $new_game_state, { thrust => 1 } );
        $self->apply_translation_forces( @c );
    }

    my @old_actors = @{ $old_game_state->{actors} };
    my @new_actors = @{ $new_game_state->{actors} };
    for my $i ( 0 .. $#old_actors ) {
        my $input =
          ( $old_actors[$i]{input} eq 'player' )
          ? (
            ( time - $self->game_state->{last_input} > 10 )
            ? $self->simple_ai_step( $old_game_state->{player},
                first { $_ != $old_game_state->{player} } @{ $old_game_state->{actors} } )
            : $client_state
          )
          : $self->simple_ai_step( $old_actors[$i], $old_game_state->{player} );
        my @c = ( $old_actors[$i], $old_game_state, $new_actors[$i], $new_game_state, $input );
        $self->apply_translation_forces( @c );
        $self->apply_rotation_forces( @c );
        $self->apply_weapon_effects( @c );
    }

    for my $i ( 0 .. $#old_bullets ) {
        $new_bullets[$i]{life_time}++;
        $new_bullets[$i]{life_time} += 12
          if $new_bullets[$i]{y} > $old_game_state->{floor}
          or $new_bullets[$i]{y} < $old_game_state->{ceiling};
    }

    if ( $old_game_state->{player} ) {
        $new_game_state->{player_was_hit} = 0 if $new_game_state->{tick} - $new_game_state->{player_was_hit} > 5;
        if ( $self->was_hit( $new_game_state->{player}, $new_game_state->{bullets}, "is_player" ) ) {
            $new_game_state->{player}{damage}++;
            $new_game_state->{player_was_hit} = $new_game_state->{tick};
        }
    }

    @{ $new_game_state->{actors} } =
      grep { $_->{is_player} or !$self->was_hit( $_, $new_game_state->{bullets} ) } @{ $new_game_state->{actors} };
    @{ $new_game_state->{bullets} } = grep { $_->{life_time} <= $_->{max_life} } @{ $new_game_state->{bullets} };
    push @{ $new_game_state->{actors} },
      {
        x => $old_game_state->{player}{x} + ( 1500 * rand ) - 750,
        y => min( 0, $old_game_state->{player}{y} + ( 1500 * rand ) - 750 ),
        x_speed      => 0,
        y_speed      => 0,
        turn_speed   => ( rand() * 5 ) + 1,
        rot          => 180,
        thrust_power => rand() + 0.2,
        max_speed    => 8,
        thrust_stall => 0.05,
        grav_cancel  => 0.3,
        gun_heat     => 0,
        gun_cooldown => 1,
        gun_use_heat => 60,
        input        => 'computer',
      }
      if $old_game_state->{player} and @{ $new_game_state->{actors} } < 10;

    if ( !$old_game_state->{player} ) {
        my %player = (
            x            => 0,
            y            => 0,
            x_speed      => 0,
            y_speed      => -32,
            turn_speed   => 5,
            rot          => 180,
            thrust_power => 1,
            max_speed    => 10,
            thrust_stall => 0.05,
            grav_cancel  => 0.3,
            gun_heat     => 0,
            gun_cooldown => 1,
            gun_use_heat => 10,
            damage       => 0,
            input        => 'player',
            is_player    => 1,
        );
        $new_game_state->{player} = \%player;
        push @{ $new_game_state->{actors} }, \%player;
    }

    return;
}

sub was_hit {
    my ( $self, $player, $bullets, $is_player ) = @_;

    my $player_vec = NewVec( $player->{x}, $player->{y} );
    for my $bullet ( @{$bullets} ) {
        next if ( $is_player and $bullet->{is_player} ) or ( ( !$is_player and !$bullet->{is_player} ) );
        my $distance = NewVec( $player_vec->Minus( [ $bullet->{x}, $bullet->{y} ] ) )->Length;
        return 1 if $distance <= 32;
    }

    return;
}

sub apply_weapon_effects {
    my ( $self, $old_player, $old_game_state, $new_player, $new_game_state, $input, $is_player ) = @_;
    $new_player->{gun_heat} -= $old_player->{gun_cooldown} if $old_player->{gun_heat} > 0;
    if ( $input->{fire} and $old_player->{gun_heat} <= 0 ) {
        push @{ $new_game_state->{bullets} },
          {
            max_speed    => 13,
            thrust_power => 9,
            thrust_stall => 9,
            x_speed      => $new_player->{x_speed},
            y_speed      => $new_player->{y_speed},
            x            => $new_player->{x},
            y            => $new_player->{y},
            rot          => $new_player->{rot},
            life_time    => 0,
            max_life     => 60,
            grav_cancel  => 0,
            is_player    => $old_player->{is_player},
          };
        $new_player->{gun_heat} += $old_player->{gun_use_heat};
    }
    return;
}

sub simple_ai_step {
    my ( $self, $computer, $player ) = @_;
    return if !$player;

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
    my $fire       = abs( $angle_to_player ) < 15;

    return { turn_left => $turn_left, turn_right => $turn_right, thrust => $thrust, fire => $fire };
}

sub apply_translation_forces {
    my ( $self, $old_player, $old_game_state, $new_player, $new_game_state, $client_state ) = @_;

    my $x_speed_delta = 0;
    my $y_speed_delta = 0;

    my $stalled = ( $old_player->{y} > $old_game_state->{floor} or $old_player->{y} < $old_game_state->{ceiling} );
    my $gravity = $old_game_state->{gravity};
    $gravity *= $old_player->{grav_cancel} if $client_state->{thrust} and !$stalled;
    $gravity *= -1 if $old_player->{y} > $old_game_state->{floor};
    $y_speed_delta += $gravity;

    if ( $client_state->{thrust} ) {
        my $rad_rot      = deg2rad $old_player->{rot};
        my $thrust_power = $old_player->{thrust_power};
        $thrust_power = $old_player->{thrust_stall} if $stalled;
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

    my $stall_color = $game_state->{player_was_hit} ? 0xff_ff_ff_88 : 0xff_ff_ff_44;
    $world->draw_line(
        [ ( $world->w * $_ - $player->{x} ) % $world->w, 0, ],
        [ ( $world->w * $_ - $player->{x} ) % $world->w, $world->h ],
        $stall_color, 0
    ) for qw( 0.25 0.5 0.75 1 );

    $world->draw_line(
        [ 0, ( $world->h * $_ - $player->{y} ) % $world->h ],
        [ $world->w, ( $world->h * $_ - $player->{y} ) % $world->h ],
        $stall_color, 0
    ) for qw( 0.25 0.5 0.75 1 );

    my $sprite = $self->player_sprite;
    for my $flier ( $player, @{ $game_state->{actors} } ) {

        $sprite->x( $flier->{x} - $player->{x} + $world->w / 2 - $sprite->{orig_surface}->w / 4 );
        $sprite->y( $flier->{y} - $player->{y} + $world->h / 2 - $sprite->{orig_surface}->h / 4 );
        $sprite->rotation( $flier->{rot} + 180 );
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

    my $bullet_sprite = $self->bullet_sprite;
    for my $bullet ( @{ $game_state->{bullets} } ) {
        $bullet_sprite->x( $bullet->{x} - $player->{x} + $world->w / 2 - $sprite->{orig_surface}->w / 8 );
        $bullet_sprite->y( $bullet->{y} - $player->{y} + $world->h / 2 - $sprite->{orig_surface}->h / 8 );
        $bullet_sprite->draw( $world );
    }

    return;
}

sub render_ui {
    my ( $self, $game_state ) = @_;
    $self->draw_gfx_text( [ 0, 0 ],             0xff_ff_ff_ff, "Controls: left up right d - Quit: q" );
    $self->draw_gfx_text( [ 0, $self->h - 40 ], 0xff_ff_ff_ff, "Damage: " . $self->game_state->{player}{damage} );
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
