package Microidium::ClientRole;

# VERSION

use lib '..';
use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d n o l );
use List::Util qw( min max );
use Carp::Always;
use Microidium::Helpers 'dfile';
use PryoNet::Client;
use Acme::MITHALDU::XSGrabBag qw' deg2rad mix ';
use Time::HiRes 'time';
use POSIX 'floor';

use Moo::Role;

requires "update_game_state";

has sounds => (
    is      => 'lazy',
    builder => sub {
        my %sounds = map { $_ => SDL::Mixer::Samples::load_WAV( dfile "$_.wav" ) } qw( shot death );
        return \%sounds;
    }
);
has pryo => ( is => 'lazy', builder => 1 );
has console => ( is => 'ro', default => sub { [ time, qw( a b c ) ] } );
has last_network_state => ( is => 'rw' );
around update_game_state => \&client_update_game_state;
has last_player_hit      => ( is => 'rw', default => sub { 0 } );
after update_game_state  => \&update_last_player_hit;
has in_network_game   => ( is => 'rw' );
has local_player_id   => ( is => 'rw' );
has network_player_id => ( is => 'rw' );
has team_colors =>
  ( is => 'ro', default => sub { { 1 => [ .9, .9, .9, 1 ], 2 => [ .9, .7, .2, 1 ], 3 => [ .2, .8, 1, 1 ] } } );
has music_is_playing => ( is => 'rw' );

my %trails;

1;

sub _build_pryo {
    my ( $self ) = @_;
    my $pryo = PryoNet::Client->new( client => shift );
    $pryo->add_listeners(
        connected    => sub { $self->in_network_game( 1 ) },
        disconnected => sub {
            $self->in_network_game( 0 );
            $self->network_player_id( 0 );
        },
        received => sub {
            my ( $connection, $frame ) = @_;
            $self->log( "got: " . ( ref $frame ? ( $frame->{tick} || "input" ) : $frame ) );
            if ( ref $frame and $frame->{tick} ) {
                $self->last_network_state( $frame );
            }
            elsif ( ref $frame and $frame->{network_player_id} ) {
                $self->log( "got network id: $frame->{network_player_id}" );
                $self->network_player_id( $frame->{network_player_id} );
            }
            return;
        },
    );
    return $pryo;
}

sub _build_client_state {
    {
        fire       => 0,
        thrust     => 0,
        turn_left  => 0,
        turn_right => 0,
        camera     => { x => 0, y => 0 },
    };
}

sub client_update_game_state {
    my ( $orig, $self, @args ) = @_;
    $self->pryo->loop->loop_once( 0 );
    return $self->network_update_game_state( @args ) if $self->in_network_game;
    return $self->local_update_game_state( $orig, @args );
}

sub network_update_game_state {
    my ( $self, $new_game_state ) = @_;
    return if !$self->last_network_state;
    %{$new_game_state} = %{ $self->last_network_state };
    $self->last_network_state( undef );
    return;
}

sub local_update_game_state {
    my ( $self, $orig, $new_game_state, @args ) = @_;
    if ( !$self->local_player_id ) {
        $new_game_state->{players}{1} = { id => 1, actor => undef };
        $self->local_player_id( 1 );
    }
    return $self->$orig( $new_game_state, @args );
}

sub update_last_player_hit {
    my ( $self, $new_game_state ) = @_;
    my $old_game_state = $self->game_state;
    my $old_player_id  = $old_game_state->{player};
    return if !$old_player_id;
    my $old_player = $old_player_id ? $old_game_state->{actors}{$old_player_id} : undef;
    my $new_player = $new_game_state->{actors}{$old_player_id};
    $self->last_player_hit( time ) if $old_player and $new_player and $old_player->{hp} > $new_player->{hp};
    return;
}

sub player_control {
    my ( $self, $actor ) = @_;
    return $self->client_state if time - $self->game_state->{last_input} <= 10;
    return $self->computer_ai( $actor, $self->game_state );
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
    $self->change_fov( $self->fov - 10 ) if $sym == SDLK_o;
    $self->change_fov( $self->fov + 10 ) if $sym == SDLK_l;

    if ( $self->in_network_game ) {
        $self->log( "sent: DOWN $sym" );
        $self->pryo->send_tcp( $self->client_state );
    }
    return;
}

sub on_keyup {
    my ( $self, $event ) = @_;
    my $sym = $event->key_sym;
    $self->client_state->{thrust}     = 0 if $sym == SDLK_UP;
    $self->client_state->{turn_left}  = 0 if $sym == SDLK_LEFT;
    $self->client_state->{turn_right} = 0 if $sym == SDLK_RIGHT;
    $self->client_state->{fire}       = 0 if $sym == SDLK_d;
    $self->connect if $sym == SDLK_n;
    if ( $self->in_network_game ) {
        $self->log( "sent: UP $sym" );
        $self->pryo->send_tcp( $self->client_state );
    }
    return;
}

sub connect {
    my ( $self ) = @_;
    return if $self->in_network_game;
    $self->pryo->connect( "127.0.0.1", 19366 );
    return;
}

my @thrusts = qw( is_thrusting is_turning_left is_turning_right );
my %cam_effect_accums = map( ( $_ => [ ( 0 ) x 30 ] ), @thrusts );

my %spring = (
    anchor_pos => -50,
    length     => 50,
    stiffness  => -100,
    damping    => -2.4,
    mass       => .1,
    mass_pos   => [ 0, 0 ],
    mass_vel   => [ 0, 0 ],
);

sub render_world {
    my ( $self, $game_state ) = @_;

    if ( !$self->music_is_playing ) {
        my $music = SDL::Mixer::Music::load_MUS( dfile 'vecinec22.ogg' );
        SDL::Mixer::Music::volume_music( 30 );
        die "music playback error" if SDL::Mixer::Music::play_music( $music, -1 ) == -1;
        $self->music_is_playing( 1 );
    }

    my $player_actor = $self->local_player_actor;
    my $cam          = $self->client_state->{camera};

    if ( $player_actor ) {
        for my $thrust ( @thrusts ) {
            push @{ $cam_effect_accums{$thrust} }, $player_actor->{$thrust};
            shift @{ $cam_effect_accums{$thrust} };
        }
        my %cam_effects = map( { $_ => ( ( grep { $_ } @{ $cam_effect_accums{$_} } ) > 20 ) } @thrusts );

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
            my $max_dist = 400;
            my $dist = ( ( $event->{x} - $player_actor->{x} )**2 + ( $event->{y} - $player_actor->{y} )**2 )**0.5;
            next if $dist > $max_dist;
            my $max_force = 20;
            my $force = 1 + ( $max_force - 1 ) * ( ( 4 / ( 3 * ( $dist / $max_dist + 1 )**2 ) ) - 1 / 3 );
            $spring{mass_pos}[$_] += 0 - $force + rand( 2 * $force ) for 0 .. 1;
        }
    }

    for my $event ( @{ $game_state->{events} } ) {
        next if $event->{type} ne "bullet_fired";
        my $actor = $game_state->{actors}{ $event->{owner} };
        next if !$actor->{player_id};
        next if $actor->{player_id} != $self->player_id;
        $spring{mass_pos}[$_] += -10 + rand 20 for 0 .. 1;
    }

    for my $i ( 0 .. 1 ) {
        next if $spring{mass_pos}[$i] < 1 and .2 > abs $spring{mass_vel}[$i];
        my $spring_force = $spring{stiffness} * ( $spring{mass_pos}[$i] - $spring{anchor_pos} - $spring{length} );
        my $damp_force   = $spring{damping} * $spring{mass_vel}[$i];
        my $acceleration = ( $spring_force + $damp_force ) / $spring{mass};
        $spring{mass_vel}[$i] += $acceleration * 1 / 60;
        $spring{mass_pos}[$i] += $spring{mass_vel}[$i] * 1 / 60;
        $cam->{ $i ? "x" : "y" } += $spring{mass_pos}[$i];
    }

    my $highlight = ( $self->last_player_hit > time - 2 );

    my $STAR_SEED    = 0x9d2c5680;
    my $tile_size    = 512;
    my $max_bg_depth = 2;            # this relates to $screen_bg_mult, but i'm not sure how

    my $w = $self->display_scale * $self->aspect_ratio;
    my $h = $self->display_scale;
    my $c = $self->team_colors;

    my %actors = %{ $game_state->{actors} };

    $self->with_sprite_setup(
        sub {
            my $screen_bottom = $cam->{y} - $h;
            my $screen_left   = $cam->{x} - $w;
            my $screen_top    = $cam->{y} + $h;
            my $screen_right  = $cam->{x} + $w;
            $self->send_sprite_data( [ 0,             0 ],              [ 1, 1, 1, 999999 ], 0, 0.2, "bullet", );
            $self->send_sprite_data( [ $screen_left,  $screen_bottom ], [ 1, 1, 1, 999999 ], 0, 0.2, "bullet", );
            $self->send_sprite_data( [ $screen_left,  $screen_top ],    [ 1, 1, 1, 999999 ], 0, 0.2, "bullet", );
            $self->send_sprite_data( [ $screen_right, $screen_bottom ], [ 1, 1, 1, 999999 ], 0, 0.2, "bullet", );
            $self->send_sprite_data( [ $screen_right, $screen_top ],    [ 1, 1, 1, 999999 ], 0, 0.2, "bullet", );

            my $screen_bg_mult = 2.9;    # this relates to $max_bg_depth and fov, but i'm not sure how
            my $screen_bottom_bg = $cam->{y} - $h * $screen_bg_mult;
            my $screen_left_bg   = $cam->{x} - $w * $screen_bg_mult;
            my $screen_top_bg    = $cam->{y} + $h * $screen_bg_mult;
            my $screen_right_bg  = $cam->{x} + $w * $screen_bg_mult;

            my $sprite_target_radius = 600;
            my $sprite_mult          = 2 * 2 * $sprite_target_radius / $self->sprite_size;
            my $camera_tile_y        = floor( $cam->{y} / $tile_size );
            my $camera_tile_x        = floor( $cam->{x} / $tile_size );

            my $bottom_start = $camera_tile_y * $tile_size;
            while ( $bottom_start + $tile_size + $sprite_target_radius > $screen_bottom_bg ) {
                $bottom_start -= $tile_size;
            }

            my $top_end = $camera_tile_y * $tile_size;
            while ( $top_end - $sprite_target_radius < $screen_top_bg ) {
                $top_end += $tile_size;
            }

            my $left_start = $camera_tile_x * $tile_size;
            while ( $left_start + $tile_size + $sprite_target_radius > $screen_left_bg ) {
                $left_start -= $tile_size;
            }

            my $right_end = $camera_tile_x * $tile_size;
            while ( $right_end - $sprite_target_radius < $screen_right_bg ) {
                $right_end += $tile_size;
            }

            my @sprites;
            for my $y_tile ( ( $bottom_start / $tile_size ) .. ( $top_end / $tile_size ) ) {
                my $j = $y_tile * $tile_size;
                for my $x_tile ( ( $left_start / $tile_size ) .. ( $right_end / $tile_size ) ) {
                    my $i = $x_tile * $tile_size;
                    my $hash = mix( $STAR_SEED, $i, $j );
                    for ( 1 .. 1 ) {
                        my $px = $i + ( $hash % $tile_size );
                        $hash >>= 3;
                        my $py = $j + ( $hash % $tile_size );
                        $hash >>= 3;
                        my $pz = "0.$hash" * $max_bg_depth;
                        $hash >>= 3;
                        my $color =
                          $py > $game_state->{ceiling} ? $c->{2} : $py < $game_state->{floor} ? $c->{3} : $c->{1};
                        push @sprites, [ [ $px, $py, $pz ], $color, 0, $sprite_mult, "blob" ];
                    }
                }
            }

            $actors{ $_->{bullet}{id} }{blink_until} = time + 0.067
              for grep { $_->{type} eq "bullet_fired" } @{ $game_state->{events} };

            my $max_trail = 45;

            for my $flier ( values %actors ) {
                my @color = @{
                    $flier->{is_bullet} ? (
                        ( $flier->{blink_until} and $flier->{blink_until} >= time )    #
                        ? [ 0, 0, 0, 1 ]
                        : $c->{ $flier->{team} }
                      )
                    : $c->{ $flier->{team} }
                };
                if (   $flier->{y} < $self->game_state->{floor}
                    or $flier->{y} > $self->game_state->{ceiling} )
                {
                    $color[$_] *= 0.5 for 0 .. 2;
                }
                push @sprites,
                  [
                    [ $flier->{x}, $flier->{y}, ],
                    $flier->{is_bullet}
                    ? ( \@color, 0, .3, "bullet", )
                    : ( \@color, $flier->{rot}, 1.5, "player1", )
                  ];

                if ( !$flier->{is_bullet} ) {
                    my $trail = $trails{ $flier->{id} } ||= { team => $flier->{team}, id => $flier->{id} };
                    push @{ $trail->{segments} },
                      [ map( $_ - 2.5 + rand 5, $flier->{x}, $flier->{y} ), $flier->{is_thrusting} ? 1 : 0.3 ];
                    shift @{ $trail->{segments} } while @{ $trail->{segments} } > $max_trail;

                    my @color = @{ $c->{ $flier->{team} } };
                    $color[3] *= 0.2
                      if $flier->{y} < $self->game_state->{floor}
                      or $flier->{y} > $self->game_state->{ceiling};
                    my %flames = qw(
                      is_thrusting     thrust_flame
                      is_turning_right thrust_right_flame
                      is_turning_left  thrust_left_flame
                    );
                    push @sprites, [ [ $flier->{x}, $flier->{y}, ], \@color, $flier->{rot}, 1.5, $flames{$_} ]
                      for grep { $flier->{$_} } keys %flames;
                }
            }

            for my $trail ( values %trails ) {
                if ( !$actors{ $trail->{id} } ) {
                    shift @{ $trail->{segments} };
                    if ( !@{ $trail->{segments} } ) {
                        delete $trails{ $trail->{id} };
                        next;
                    }
                }

                my @color = map { "$_" } @{ $c->{ $trail->{team} } }[ 0 .. 2 ];
                my $alpha = 0;

                $_ *= 1.5 for @color;

                for my $i ( 0 .. $#{ $trail->{segments} } - 2 ) {
                    my $segment = $trail->{segments}[$i];
                    $alpha += 1 / $max_trail;
                    my $seg_alpha = $segment->[2] * $alpha;
                    $seg_alpha *= 0.2
                      if $segment->[1] < $self->game_state->{floor}
                      or $segment->[1] > $self->game_state->{ceiling};
                    push @sprites, [ [ $segment->[0], $segment->[1] ], [ @color, $seg_alpha ], 0, 0.5, "blob" ];
                }
            }

            $self->send_sprite_datas( @sprites );
        }
    );

    my $audio_pickup = $player_actor ? $player_actor : $cam;

    my @new_bullets = grep $_->{is_bullet}, map $actors{$_}, @{ $game_state->{new_actors} };
    $self->play_sound( "shot", $_, $audio_pickup, 3 ) for @new_bullets;

    my @dead_planes = grep !$_->{is_bullet}, @{ $game_state->{removed_actors} };
    $self->play_sound( "death", $_, $audio_pickup, 3 ) for @dead_planes;

    return;
}

sub play_sound {
    my ( $self, $sound_id, $flier, $cam, $falloff ) = @_;

    my $x_diff = $flier->{x} - $cam->{x};
    my $distance = ( ( ( $x_diff )**2 ) + ( ( $flier->{y} - $cam->{y} )**2 ) )**0.5;
    $distance /= $falloff;
    return if $distance > 255;

    my $angle = $x_diff / $falloff;
    $angle = $angle >= 0 ? ( min $angle, 90 ) : ( 360 + max $angle, -90 );

    my $channel = SDL::Mixer::Channels::play_channel( -1, $self->sounds->{$sound_id}, 0 );
    SDL::Mixer::Channels::volume( $channel, 30 );
    SDL::Mixer::Effects::set_position( $channel, $angle, $distance );
    return;
}

sub render_ui {
    my ( $self, $game_state ) = @_;
    my $player_actor = $self->local_player_actor;
    $self->print_text_2D( [ 0, $self->height - 12 ],
        "Controls: left up right d - Quit: q - Connect to server: n - Zoom in/out: o l" );

    $self->print_text_2D( [ 0, 60 ], sprintf "Sprites: %d", $self->sprite_count );

    $self->print_text_2D(
        [ 0, 50 ],
        sprintf "Audio channels:|%s|",
        join "", map { SDL::Mixer::Channels::playing( $_ ) ? 'x' : ' ' } 0 .. 31
    );
    $self->print_text_2D( [ 0, 40 ], "HP: $player_actor->{hp}" ) if $player_actor;
    $self->print_text_2D(
        [ 0, 30 ],
        "X Y R Speed: " . join ' ',
        map sprintf( "% 8.2f", $_ ),
        ( map $player_actor->{$_}, qw( x y rot ) ),
        ( $player_actor->{x_speed}**2 + $player_actor->{y_speed}**2 )**0.5
    ) if $player_actor;
    $self->print_text_2D(
        [ 0, 20 ],
        sprintf "FPS / Frame / Render / World / UI: %5.1f / %6.2f ms / %6.2f ms / %6.2f ms / %6.2f ms",
        1 / $self->frame_time,
        $self->frame_time * 1000,
        $self->render_time * 1000,
        $self->world_time * 1000,
        $self->ui_time * 1000,
    );
    $self->print_text_2D( [ 0, 10 ], "Frame: " . $self->frame );
    $self->print_text_2D( [], "Tick: " . $game_state->{tick} ) if $game_state->{tick};

    my $con = $self->console;
    my @to_display = grep defined, @{$con}[ max( 0, $#$con - 10 ) .. $#$con ];
    $self->print_text_2D( [ 0, $self->height - 22 - $_ * 10 ], $to_display[$_] ) for 0 .. $#to_display;

    return;
}

sub player_id {
    my ( $self ) = @_;
    return $self->in_network_game ? $self->network_player_id : $self->local_player_id;
}

sub local_player {
    my ( $self ) = @_;
    my $player_id = $self->player_id;
    return $player_id ? $self->game_state->{players}{$player_id} : undef;
}

sub local_player_actor {
    my ( $self ) = @_;
    my $player = $self->local_player;
    return $player && $player->{actor} ? $self->game_state->{actors}{ $player->{actor} } : undef;
}

sub log { push @{ shift->console }, @_ }
