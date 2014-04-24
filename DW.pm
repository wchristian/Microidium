package DW;

use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d );
use Math::Trig qw' deg2rad rad2deg ';
use SDLx::Sprite;
use Math::Vec qw(NewVec);
use List::Util qw( first min );
use Carp::Always;
use curry;

use Moo;

has player_sprites => (
    is      => 'ro',
    default => sub {
        return { map { $_ => SDLx::Sprite->new( image => "player$_.png" ) } 1 .. 3, };
    }
);
has bullet_sprite => ( is => 'ro', default => sub { SDLx::Sprite->new( image => "bullet.png" ) } );
with 'FW';

__PACKAGE__->new->run if !caller;

1;

sub _build_client_state {
    {
        fire       => 0,
        thrust     => 0,
        turn_left  => 0,
        turn_right => 0,
        zoom       => 1,
        camera     => { x => 0, y => 0 },
    };
}

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick           => 0,
        last_input     => 0,
        player         => undef,
        actors         => {},
        last_actor_id  => 0,
        player_was_hit => 0,
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

sub new_actor_id {
    my ( $self, $state ) = @_;
    return ++$state->{last_actor_id};
}

sub add_actor_to {
    my ( $self, $game_state, $actor ) = @_;
    $actor->{id} = $self->new_actor_id( $game_state );
    $game_state->{actors}{ $actor->{id} } = $actor;
    return;
}

sub update_game_state {
    my ( $self, $new_game_state, $client_state ) = @_;
    $new_game_state->{tick}++;

    my $old_game_state = $self->game_state;
    my $old_actors     = $old_game_state->{actors};
    my $new_actors     = $new_game_state->{actors};
    for my $id ( keys %{$old_actors} ) {
        my $actor = $old_actors->{$id};
        my $input = $actor->{input}->( $actor );
        my @c     = ( $actor, $new_actors->{$id}, $new_game_state, $input );
        $self->apply_translation_forces( @c );
        $self->apply_rotation_forces( @c );
        $self->apply_weapon_effects( @c );
        $self->apply_location_damage( @c );
        $self->apply_collision_effects( @c );
        delete $new_actors->{$id} if $new_actors->{$id}{hp} <= 0;
    }

    my $old_player_id = $old_game_state->{player};
    my $old_player = $old_player_id ? $old_game_state->{actors}{$old_player_id} : undef;
    $new_game_state->{player} = undef if !$old_player;
    if ( $old_player ) {
        my $new_player = $new_game_state->{actors}{$old_player_id};

        $new_game_state->{player_was_hit} = 0 if $new_game_state->{tick} - $new_game_state->{player_was_hit} > 5;
        $new_game_state->{player_was_hit} = $new_game_state->{tick}
          if $new_player->{hp} and $old_player->{hp} > $new_player->{hp};

        $self->add_actor_to(
            $new_game_state,
            {
                x => $old_player->{x} + ( 1500 * rand ) - 750,
                y => min( 0, $old_player->{y} + ( 1500 * rand ) - 750 ),
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
                input        => $self->curry::computer_ai,
                team         => ( rand > 0.5 ) ? 2 : 3,
                hp           => 1,
            }
        ) if ( grep { !$_->{is_bullet} } values %{ $new_game_state->{actors} } ) < 10;
    }

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
            input        => $self->curry::player_control,
            team         => 1,
            hp           => 12,
        );
        $self->add_actor_to( $new_game_state, \%player );
        $new_game_state->{player} = $player{id};
    }

    return;
}

sub apply_collision_effects {
    my ( $self, $actor, $new_actor, $new_game_state, $input ) = @_;
    my @collisions = $self->collisions( $actor, $self->game_state->{actors} );
    for my $other ( @collisions ) {
        $new_actor->{hp} -= 1 if $other->{team} != $actor->{team};
    }
    return;
}

sub collisions {
    my ( $self, $actor, $actors ) = @_;
    my $actor_vec = NewVec( $actor->{x}, $actor->{y} );
    my @collided = grep { 32 > NewVec( $actor_vec->Minus( [ $_->{x}, $_->{y} ] ) )->Length } values %{$actors};
    return @collided;
}

sub computer_ai {
    my ( $self, $actor ) = @_;
    delete $actor->{enemy} if $actor->{enemy} and !$self->game_state->{actors}{ $actor->{enemy} };
    $actor->{enemy} ||= $self->find_enemy( $actor );
    return $self->simple_ai_step( $actor, $actor->{enemy} );
}

sub find_enemy {
    my ( $self, $actor ) = @_;
    my @possible_enemies =
      grep { !$_->{is_bullet} and $_->{team} != $actor->{team} } values %{ $self->game_state->{actors} };
    return if !@possible_enemies;
    my $id = int( rand() * @possible_enemies );
    return $possible_enemies[$id]->{id};
}

sub player_control {
    my ( $self, $actor ) = @_;
    return $self->client_state if time - $self->game_state->{last_input} <= 10;
    return $self->computer_ai( $actor, $self->game_state );
}

sub apply_location_damage {
    my ( $self, $actor, $new_actor, $new_game_state, $input ) = @_;
    return if !$actor->{hp_loss_speed};

    my $game_state = $self->game_state;
    my $loss_key =
        ( $actor->{y} > $game_state->{floor} )   ? 'floor'
      : ( $actor->{y} < $game_state->{ceiling} ) ? 'ceil'
      :                                            'normal';
    $new_actor->{hp} -= $actor->{hp_loss_speed}{$loss_key};
    return;
}

sub apply_weapon_effects {
    my ( $self, $old_player, $new_player, $new_game_state, $input ) = @_;
    return if $old_player->{is_bullet};
    $new_player->{gun_heat} -= $old_player->{gun_cooldown} if $old_player->{gun_heat} > 0;
    if ( $input->{fire} and $old_player->{gun_heat} <= 0 ) {
        my %bullet = (
            max_speed     => 13,
            thrust_power  => 9,
            thrust_stall  => 9,
            x_speed       => $new_player->{x_speed},
            y_speed       => $new_player->{y_speed},
            x             => $new_player->{x},
            y             => $new_player->{y},
            rot           => $new_player->{rot},
            hp            => 60,
            hp_loss_speed => {
                normal => 1,
                floor  => 12,
                ceil   => 12,
            },
            grav_cancel => 0,
            team        => $old_player->{team},
            is_bullet   => 1,
            input       => sub { { thrust => 1 } },
        );
        $self->add_actor_to( $new_game_state, \%bullet );
        $new_player->{gun_heat} += $old_player->{gun_use_heat};
    }
    return;
}

sub simple_ai_step {
    my ( $self, $computer, $player ) = @_;
    $player = $self->game_state->{actors}{ $computer->{enemy} } if $computer->{enemy};
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
    my ( $self, $old_player, $new_player, $new_game_state, $client_state ) = @_;

    my $x_speed_delta = 0;
    my $y_speed_delta = 0;

    my $old_game_state = $self->game_state;
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
    my ( $self, $old_player, $new_player, $new_game_state, $client_state ) = @_;
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
    my $player = $game_state->{player} ? $game_state->{actors}{ $game_state->{player} } : undef;
    my $cam = $self->client_state->{camera};
    @{$cam}{qw(x y)} = @{$player}{qw(x y)} if $player;

    if ( ( my $ceil_height = $world->h / 2 - $cam->{y} + $game_state->{ceiling} ) >= 0 ) {
        $world->draw_rect( [ 0, 0, $world->w, $ceil_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $ceil_height ], [ $world->w, $ceil_height ], 0xff_ff_ff_ff, 0 );
    }

    if ( ( my $floor_height = $world->h / 2 - $cam->{y} + $game_state->{floor} ) <= $world->h ) {
        $world->draw_rect( [ 0, $floor_height, $world->w, $world->h - $floor_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $floor_height ], [ $world->w, $floor_height ], 0xff_ff_ff_ff, 0 );
    }

    my $stall_color = $game_state->{player_was_hit} ? 0xff_ff_ff_88 : 0xff_ff_ff_44;
    $world->draw_line(
        [ ( $world->w * $_ - $cam->{x} ) % $world->w, 0, ],
        [ ( $world->w * $_ - $cam->{x} ) % $world->w, $world->h ],
        $stall_color, 0
    ) for qw( 0.25 0.5 0.75 1 );

    $world->draw_line(
        [ 0, ( $world->h * $_ - $cam->{y} ) % $world->h ],
        [ $world->w, ( $world->h * $_ - $cam->{y} ) % $world->h ],
        $stall_color, 0
    ) for qw( 0.25 0.5 0.75 1 );

    my $sprites       = $self->player_sprites;
    my $bullet_sprite = $self->bullet_sprite;
    for my $flier ( $player, values %{ $game_state->{actors} } ) {
        next if !$flier;
        my $sprite = $sprites->{ $flier->{team} };
        if ( $flier->{is_bullet} ) {
            $bullet_sprite->x( $flier->{x} - $cam->{x} + $world->w / 2 - $sprite->{orig_surface}->w / 8 );
            $bullet_sprite->y( $flier->{y} - $cam->{y} + $world->h / 2 - $sprite->{orig_surface}->h / 8 );
            $bullet_sprite->draw( $world );
        }
        else {

            $sprite->x( $flier->{x} - $cam->{x} + $world->w / 2 - $sprite->{orig_surface}->w / 4 );
            $sprite->y( $flier->{y} - $cam->{y} + $world->h / 2 - $sprite->{orig_surface}->h / 4 );
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
    }

    return;
}

sub render_ui {
    my ( $self, $game_state ) = @_;
    my $player = $game_state->{player} ? $game_state->{actors}{ $game_state->{player} } : undef;
    $self->draw_gfx_text( [ 0, 0 ], 0xff_ff_ff_ff, "Controls: left up right d - Quit: q" );
    $self->draw_gfx_text( [ 0, $self->h - 40 ], 0xff_ff_ff_ff, "HP: $player->{hp}" ) if $player;
    $self->draw_gfx_text(
        [ 0, $self->h - 32 ],
        0xff_ff_ff_ff, join ' ',
        ( map $player->{$_}, qw( x y rot ) ),
        ( $player->{x_speed}**2 + $player->{y_speed}**2 )**0.5
    ) if $player;
    $self->draw_gfx_text( [ 0, $self->h - 24 ], 0xff_ff_ff_ff, $self->fps );
    $self->draw_gfx_text( [ 0, $self->h - 16 ], 0xff_ff_ff_ff, $self->frame );
    $self->draw_gfx_text( [ 0, $self->h - 8 ],  0xff_ff_ff_ff, $game_state->{tick} );
    return;
}
