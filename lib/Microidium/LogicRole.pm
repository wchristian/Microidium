package Microidium::LogicRole;

# VERSION

use List::Util qw( first min max );
use Math::Trig qw' deg2rad rad2deg ';
use Math::Vec ();

use Moo::Role;

has planned_new_actors => ( is => 'rw', default => sub { [] } );

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick           => 0,
        last_input     => 0,
        player         => undef,
        actors         => {},
        last_actor_id  => 0,
        ceiling        => -1800,
        floor          => 0,
        gravity        => 0.15,
    };
}

sub update_game_state {
    my ( $self, $new_game_state ) = @_;

    $self->planned_new_actors( [] );

    $new_game_state->{tick}++;

    $self->modify_actors( $new_game_state );    # new gamestate guaranteed to not have new or removed actors
    $self->remove_actors( $new_game_state );

    my $old_game_state = $self->game_state;
    my $old_player_id  = $old_game_state->{player};
    my $old_player     = $old_player_id ? $old_game_state->{actors}{$old_player_id} : undef;
    $new_game_state->{player} = undef if !$old_player;
    if ( $old_player ) {
        $self->plan_actor_addition(
            $new_game_state,
            {
                x            => $old_player->{x} - 750 + rand 1500,
                y            => min( 0, $old_player->{y} - 750 + rand 1500 ),
                x_speed      => 0,
                y_speed      => 0,
                turn_speed   => 1 + rand 5,
                rot          => 180,
                thrust_power => 0.2 + rand,
                max_speed    => 8,
                thrust_stall => 0.05,
                grav_cancel  => 0.3,
                gun_heat     => 0,
                gun_cooldown => 1,
                gun_use_heat => 60,
                input        => "computer_ai",
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
            input        => "player_control",
            team         => 1,
            hp           => 12,
        );
        $self->plan_actor_addition( $new_game_state, \%player );
        $new_game_state->{player} = $player{id};
    }

    $self->add_planned_actors( $new_game_state );

    return;
}

sub modify_actors {
    my ( $self, $new_game_state ) = @_;

    my $old_game_state = $self->game_state;
    my $old_actors     = $old_game_state->{actors};
    my $new_actors     = $new_game_state->{actors};
    for my $id ( keys %{$old_actors} ) {
        my $actor      = $old_actors->{$id};
        my $input_meth = $actor->{input};
        my $input      = $self->$input_meth( $actor );
        my @c          = ( $actor, $new_actors->{$id}, $new_game_state, $input );
        $self->apply_translation_forces( @c );
        $self->apply_rotation_forces( @c );
        $self->apply_weapon_effects( @c );
        $self->apply_location_damage( @c );
        $self->apply_collision_effects( @c );
    }
    return;
}

sub remove_actors {
    my ( $self, $new_game_state ) = @_;
    my $new_actors = $new_game_state->{actors};
    delete $new_actors->{ $_->{id} } for grep { $_->{hp} <= 0 } values %{$new_actors};
    return;
}

sub add_planned_actors {
    my ( $self, $new_game_state ) = @_;
    $new_game_state->{actors}{ $_->{id} } = $_ for @{ $self->planned_new_actors };
    $self->planned_new_actors( [] );
    return;
}

sub plan_actor_addition {
    my ( $self, $game_state, $actor ) = @_;
    $actor->{id} = $self->new_actor_id( $game_state );
    push @{ $self->planned_new_actors }, $actor;
    return $actor->{id};
}

sub new_actor_id {
    my ( $self, $state ) = @_;
    return ++$state->{last_actor_id};
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
    my $id = int rand @possible_enemies;
    return $possible_enemies[$id]->{id};
}

sub simple_ai_step {
    my ( $self, $computer, $player ) = @_;
    $player = $self->game_state->{actors}{ $computer->{enemy} } if $computer->{enemy};
    return if !$player;

    my @vec_to_player = ( $computer->{x} - $player->{x}, $computer->{y} - $player->{y} );
    my $dot_product   = Math::Vec->new( @vec_to_player )->Dot( [ 0, -1 ] );
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
            input       => "perma_thrust",
        );
        $self->plan_actor_addition( $new_game_state, \%bullet );
        $new_player->{gun_heat} += $old_player->{gun_use_heat};
    }
    return;
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

sub apply_collision_effects {
    my ( $self, $actor, $new_actor, $new_game_state, $input ) = @_;
    for my $other ( $self->collisions( $actor, $self->game_state->{actors} ) ) {
        $new_actor->{hp} -= 1 if $other->{team} != $actor->{team};
    }
    return;
}

sub collisions {
    my ( $self, $actor, $actors ) = @_;
    return grep { 32 > sqrt( ( $actor->{x} - $_->{x} )**2 + ( $actor->{y} - $_->{y} )**2 ) } values %{$actors};
}

sub perma_thrust { { thrust => 1 } }

1;
