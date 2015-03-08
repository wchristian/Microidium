package Microidium::ClientCameraRole;

use strictures;

use constant THRUSTS => qw( is_thrusting is_turning_left is_turning_right );
use Acme::MITHALDU::XSGrabBag 'deg2rad';

use Moo::Role;

has $_ => ( is => 'ro', builder => 1 ) for qw( spring cam_effect_accums );

sub _build_cam_effect_accums {
    return { map { $_ => [ ( 0 ) x 30 ] } THRUSTS };
}

sub _build_spring {
    {
        anchor_pos => -50,
        length     => 50,
        stiffness  => -100,
        damping    => -2.4,
        mass       => .1,
        mass_pos   => [ 0, 0 ],
        mass_vel   => [ 0, 0 ]
    };
}

sub update_camera {
    my ( $self, $game_state ) = @_;

    my $player_actor = $self->local_player_actor;
    my $cam          = $self->client_state->{camera};
    my $spring       = $self->spring;

    if ( $player_actor ) {
        my $cam_effect_accums = $self->cam_effect_accums;
        for my $thrust ( THRUSTS ) {
            push @{ $cam_effect_accums->{$thrust} }, $player_actor->{$thrust};
            shift @{ $cam_effect_accums->{$thrust} };
        }
        my %cam_effects = map( { $_ => ( ( grep { $_ } @{ $cam_effect_accums->{$_} } ) > 20 ) } THRUSTS );

        my $dist = 50 + ( 650 * $cam_effects{is_thrusting} );
        $dist -= 300 if $cam_effects{is_turning_left} or $cam_effects{is_turning_right};
        $dist = 0 if $dist < 0;
        $dist *= $player_actor->{speed} / $player_actor->{max_speed};
        my $cam_x_target = $player_actor->{x} + ( $dist * sin deg2rad $player_actor->{rot} );
        my $cam_y_target = $player_actor->{y} + ( $dist * cos deg2rad $player_actor->{rot} );

        $cam_y_target = $self->game_state->{floor}   if $cam_y_target < $self->game_state->{floor};
        $cam_y_target = $self->game_state->{ceiling} if $cam_y_target > $self->game_state->{ceiling};

        my $diff_x = $cam_x_target - $cam->{x};
        my $diff_y = $cam_y_target - $cam->{y};
        my $damp   = 0.03;
        $cam->{x} += $diff_x * $damp;
        $cam->{y} += $diff_y * $damp;

        for my $event ( @{ $game_state->{events} } ) {
            next if $event->{type} ne "flier_died";
            next if $event->{is_bullet};
            my $max_dist = 400;
            my $dist = ( ( $event->{x} - $player_actor->{x} )**2 + ( $event->{y} - $player_actor->{y} )**2 )**0.5;
            next if $dist > $max_dist;
            my $max_force = 40;    # https://www.desmos.com/calculator/ygopptotiu
            my $force = 1 + ( $max_force - 1 ) * ( ( 4 / ( 3 * ( $dist / $max_dist + 1 )**2 ) ) - 1 / 3 );
            $spring->{mass_pos}[$_] += 0 - $force + rand( 2 * $force ) for 0 .. 1;
        }
    }

    for my $event ( @{ $game_state->{events} } ) {
        next if $event->{type} ne "bullet_fired";
        my $actor = $game_state->{actors}{ $event->{owner} };
        next if !$actor->{player_id};
        next if $actor->{player_id} != $self->player_id;
        $spring->{mass_pos}[$_] += -10 + rand 20 for 0 .. 1;
    }

    for my $i ( 0 .. 1 ) {
        next if $spring->{mass_pos}[$i] < 1 and .2 > abs $spring->{mass_vel}[$i];
        my $spring_force =
          $spring->{stiffness} * ( $spring->{mass_pos}[$i] - $spring->{anchor_pos} - $spring->{length} );
        my $damp_force   = $spring->{damping} * $spring->{mass_vel}[$i];
        my $acceleration = ( $spring_force + $damp_force ) / $spring->{mass};
        $spring->{mass_vel}[$i] += $acceleration * 1 / 60;
        $spring->{mass_pos}[$i] += $spring->{mass_vel}[$i] * 1 / 60;
        $cam->{ $i ? "x" : "y" } += $spring->{mass_pos}[$i];
    }

    return;
}

1;
