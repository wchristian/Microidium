package Microidium::LogicRole;

use strictures;

# VERSION

use List::Util qw( first min max );
use Acme::MITHALDU::XSGrabBag 1.150720 qw' deg2rad rad2deg ';
use Math::Vec ();
use Time::HiRes 'time';

use Moo::Role;

has planned_new_actors => ( is => 'rw', default => sub { [] } );

sub _build_game_state {
    my ( $self ) = @_;
    return {
        tick          => 0,
        last_input    => 0,
        players       => {},
        actors        => {},
        last_actor_id => 0,
        ceiling       => 3000,
        floor         => 0,
        gravity       => -0.15,
    };
}

sub update_game_state {
    my ( $self, $new_game_state ) = @_;

    $self->planned_new_actors( [] );

    $new_game_state->{new_actors}     = [];
    $new_game_state->{events}         = [];
    $new_game_state->{removed_actors} = [];
    $new_game_state->{tick}++;

    $self->modify_actors( $new_game_state );    # new gamestate guaranteed to not have new or removed actors
    $self->remove_actors( $new_game_state );
    $self->plan_bot_respawns( $new_game_state );
    $self->plan_player_respawns( $new_game_state );
    $self->add_planned_actors( $new_game_state );

    return;
}

sub plan_bot_respawns {
    my ( $self, $new_game_state ) = @_;

    my @players = grep { !$_->{is_bullet} } values %{ $new_game_state->{actors} };
    return if @players > 10;

    my @bot_start = do {
        my $old_game_state       = $self->game_state;
        my $old_players          = $old_game_state->{players};
        my ( $first_old_player ) = values %{$old_players};
        my $actor_id             = $first_old_player->{actor};
        my $actor                = $actor_id ? $old_game_state->{actors}{$actor_id} : undef;
        $actor ? ( $actor->{x}, $actor->{y} ) : ( 0, 0 );
    };

    my $team = rand > 0.5 ? 2 : 3;
    $team = 2 if $team != 2 and grep( { $_->{team} == 2 } @players ) <= 2;
    $team = 3 if $team != 3 and grep( { $_->{team} == 3 } @players ) <= 2;

    my %stats = (
        x => $bot_start[0] + ( rand > .5 ? 1 : -1 ) * ( 550 + rand 550 ),
        y                => min( 2800, max( 200, $bot_start[1] - 1500 + rand 3000 ) ),
        x_speed          => 0,
        y_speed          => 0,
        turn_speed       => 4 + rand 6,
        turn_damp        => 0.2 + rand 0.8,
        rot              => 0,
        thrust_power     => 0.2 + rand,
        speed            => 0,
        max_speed        => 8 + rand 20,
        thrust_stall     => 0.05,
        grav_cancel      => 0.3,
        gun_heat         => 0,
        gun_cooldown     => 1,
        gun_use_heat     => 60,
        input            => "computer_ai",
        team             => $team,
        hp               => 2,
        is_thrusting     => 1,
        is_turning_left  => 0,
        is_turning_right => 0,
        is_firing        => 0,
        reaction_time    => rand 0.1,
    );
    $self->plan_actor_addition( $new_game_state, \%stats );

    return;
}

sub plan_player_respawns {
    my ( $self, $new_game_state ) = @_;

    my $old_game_state = $self->game_state;
    my $old_players    = $old_game_state->{players};

    for my $player ( values %{$old_players} ) {
        my $actor_id = $player->{actor};
        next if $actor_id and $old_game_state->{actors}{$actor_id};
        my %actor = (
            x                => 0,
            y                => 200,
            x_speed          => 0,
            y_speed          => 32,
            turn_speed       => 6,
            turn_damp        => 0.5,
            rot              => 0,
            thrust_power     => 1,
            speed            => 0,
            max_speed        => 10,
            thrust_stall     => 0.05,
            grav_cancel      => 0.3,
            gun_heat         => 0,
            gun_cooldown     => 1,
            gun_use_heat     => 5,
            input            => "player_control",
            team             => 1,
            hp               => 12,
            player_id        => $player->{id},
            is_thrusting     => 1,
            is_turning_left  => 0,
            is_turning_right => 0,
            is_firing        => 0,
            reaction_time    => 0.04,
        );
        $new_game_state->{players}{ $player->{id} }{actor} = $self->plan_actor_addition( $new_game_state, \%actor );
    }

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
        $self->apply_inputs( $new_actors->{$id}, $input ) if $input;
        my @c = ( $actor, $new_actors->{$id}, $new_game_state );
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
    for my $actor ( grep { $_->{hp} <= 0 } values %{$new_actors} ) {
        $self->add_event( $new_game_state, "flier_died",
            { x => $actor->{x}, y => $actor->{y}, is_bullet => $actor->{is_bullet}, team => $actor->{team} } );
        push @{ $new_game_state->{removed_actors} }, delete $new_actors->{ $actor->{id} };
    }
    return;
}

sub add_planned_actors {
    my ( $self, $new_game_state ) = @_;
    $new_game_state->{actors}{ $_->{id} } = $_ for @{ $self->planned_new_actors };
    $new_game_state->{new_actors} = [ map $_->{id}, @{ $self->planned_new_actors } ];
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
    return if $actor->{last_decision_time} and time < $actor->{last_decision_time} + .04;

    my $actors = $self->game_state->{actors};
    delete $actor->{enemy}
      if $actor->{enemy}
      and ( !$actors->{ $actor->{enemy} }
        or $actors->{ $actor->{enemy} }->{y} < $self->too_deep );
    $actor->{enemy} ||= $self->find_enemy( $actor );

    my $decision = $self->simple_ai_step( $actor, $actor->{enemy} );
    $decision->{last_decision_time} = time;
    return $decision;
}

sub too_deep { shift->game_state->{floor} - 100 }

sub find_enemy {
    my ( $self, $actor ) = @_;
    my $too_deep = $self->too_deep;
    my @possible_enemies = grep { $_->{y} > $too_deep }
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
    my $dot_product   = $vec_to_player[0] * 0 + $vec_to_player[1] * -1;
    my $perpDot       = $vec_to_player[0] * -1 - $vec_to_player[1] * 0;
    my $angle_to_down = rad2deg atan2( $perpDot, $dot_product );
    my $comp_rot      = $computer->{rot};
    $comp_rot -= 360 if $comp_rot > 180;
    my $angle_to_player = $comp_rot - $angle_to_down;
    $angle_to_player -= 360 if $angle_to_player > 180;
    $angle_to_player += 360 if $angle_to_player < -180;

    my $turn_left  = $angle_to_player > 0;
    my $turn_right = $angle_to_player < 0;
    my $thrust     = abs( $angle_to_player ) < 50;
    my $fire       = abs( $angle_to_player ) < 15;

    return { turn_left => $turn_left, turn_right => $turn_right, thrust => $thrust, fire => $fire };
}

sub apply_inputs {
    my ( $self, $new_player, $client_state ) = @_;
    $new_player->{is_thrusting}       = $client_state->{thrust};
    $new_player->{is_turning_left}    = $client_state->{turn_left};
    $new_player->{is_turning_right}   = $client_state->{turn_right};
    $new_player->{is_firing}          = $client_state->{fire};
    $new_player->{last_decision_time} = $client_state->{last_decision_time} if $client_state->{last_decision_time};
    return;
}

sub apply_translation_forces {
    my ( $self, $old_player, $new_player, $new_game_state ) = @_;

    my $x_speed_delta = 0;
    my $y_speed_delta = 0;

    my $old_game_state = $self->game_state;
    my $stalled = ( $old_player->{y} < $old_game_state->{floor} or $old_player->{y} > $old_game_state->{ceiling} );
    my $gravity = $old_game_state->{gravity};
    $gravity *= $old_player->{grav_cancel} if $new_player->{is_thrusting} and !$stalled;
    $gravity *= -1 if $old_player->{y} < $old_game_state->{floor};
    $y_speed_delta += $gravity;

    if ( $new_player->{is_thrusting} ) {
        my $rad_rot      = deg2rad $old_player->{rot};
        my $thrust_power = $old_player->{thrust_power};
        $thrust_power = $old_player->{thrust_stall} if $stalled;
        $x_speed_delta += $thrust_power * sin $rad_rot;
        $y_speed_delta += $thrust_power * cos $rad_rot;
    }

    $new_player->{x_speed} = $old_player->{x_speed} + $x_speed_delta;
    $new_player->{y_speed} = $old_player->{y_speed} + $y_speed_delta;

    my $max_speed = $old_player->{max_speed};
    my $player_speed = $new_player->{speed} = ( $new_player->{x_speed}**2 + $new_player->{y_speed}**2 )**0.5;
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
    my ( $self, $old_player, $new_player, $new_game_state ) = @_;
    return if !$new_player->{is_turning_left} and !$new_player->{is_turning_right};

    my $sign = $new_player->{is_turning_right} ? 1 : -1;
    my $turn_speed = $old_player->{turn_speed};
    $turn_speed *= $old_player->{turn_damp} if $new_player->{is_thrusting};
    $new_player->{rot} = $old_player->{rot} + $sign * $turn_speed;
    $new_player->{rot} += 360 if $new_player->{rot} < 0;
    $new_player->{rot} -= 360 if $new_player->{rot} > 360;
    return;
}

sub apply_weapon_effects {
    my ( $self, $old_player, $new_player, $new_game_state ) = @_;
    return if $old_player->{is_bullet};
    $new_player->{gun_heat} -= $old_player->{gun_cooldown} if $old_player->{gun_heat} > 0;
    if ( $new_player->{is_firing} and $old_player->{gun_heat} <= 0 ) {
        my %bullet = (
            max_speed     => 20,
            thrust_power  => 9,
            thrust_stall  => 9,
            x_speed       => $new_player->{x_speed},
            y_speed       => $new_player->{y_speed},
            x             => $new_player->{x},
            y             => $new_player->{y},
            rot           => $new_player->{rot} + ( 7 * rand() ),
            hp            => 60,
            hp_loss_speed => {
                normal => 1,
                floor  => 12,
                ceil   => 12,
            },
            grav_cancel => 0,
            team        => $old_player->{team},
            owner       => $old_player->{id},
            is_bullet   => 1,
            input       => "perma_thrust",
        );
        $self->plan_actor_addition( $new_game_state, \%bullet );
        $new_player->{gun_heat} += $old_player->{gun_use_heat};
        $self->add_event( $new_game_state, "bullet_fired",
            { x => $bullet{x}, y => $bullet{y}, owner => $old_player->{id}, bullet => \%bullet } );
    }
    return;
}

sub add_event {
    my ( $self, $new_game_state, $event_type, $args ) = @_;
    push @{ $new_game_state->{events} }, { type => $event_type, %{$args} };
    return;
}

sub apply_location_damage {
    my ( $self, $actor, $new_actor, $new_game_state ) = @_;
    return if !$actor->{hp_loss_speed};

    my $game_state = $self->game_state;
    my $loss_key =
        ( $actor->{y} < $game_state->{floor} )   ? 'floor'
      : ( $actor->{y} > $game_state->{ceiling} ) ? 'ceil'
      :                                            'normal';
    $new_actor->{hp} -= $actor->{hp_loss_speed}{$loss_key};
    return;
}

sub apply_collision_effects {
    my ( $self, $actor, $new_actor, $new_game_state ) = @_;
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
