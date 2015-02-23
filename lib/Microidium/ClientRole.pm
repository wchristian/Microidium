package Microidium::ClientRole;

# VERSION

use lib '..';
use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d n );
use List::Util qw( min max );
use Carp::Always;
use Microidium::Helpers 'dfile';
use PryoNet::Client;
use Acme::MITHALDU::XSGrabBag qw' deg2rad mix ';

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
    my $player_actor = $self->local_player_actor;
    my $cam          = $self->client_state->{camera};

    if ( $player_actor ) {
        my $dist = 50 + ( 650 * $self->client_state->{thrust} );
        $dist -= 300 if $self->client_state->{turn_left} or $self->client_state->{turn_right};
        $dist = 0 if $dist < 0;
        my $cam_x_target = $player_actor->{x} + ( $dist * sin deg2rad $player_actor->{rot} );
        my $cam_y_target = $player_actor->{y} + ( $dist * cos deg2rad $player_actor->{rot} );
        my $diff_x       = $cam_x_target - $cam->{x};
        my $diff_y       = $cam_y_target - $cam->{y};
        my $damp         = 0.03;
        $cam->{x} += $diff_x * $damp;
        $cam->{y} += $diff_y * $damp;
    }

    for my $event ( @{ $game_state->{events} } ) {
        next if $event->{type} ne "bullet_fired";
        my $actor = $game_state->{actors}{ $event->{owner} };
        next if !$actor->{player_id};
        next if $actor->{player_id} != $self->local_player_id;
        $spring{mass_pos}[$_] += -10 + rand 20 for 0 .. 1;
    }

    for my $event ( @{ $game_state->{events} } ) {
        next if $event->{type} ne "flier_died";
        $spring{mass_pos}[$_] += -20 + rand 40 for 0 .. 1;
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

    my $STAR_SEED      = 0x9d2c5680;
    my $STAR_TILE_SIZE = 512;

    my $w = $self->w;
    my $h = $self->h;
    my $c = $self->team_colors;

    my %actors = %{ $game_state->{actors} };

    $self->with_sprite_setup(
        sub {
            for my $starscale ( 1 ) {
                my $size = $STAR_TILE_SIZE / $starscale;

                # Top-left tile's top-left position.
                my $sx = int( ( $cam->{x} - $w / 2 ) / $size ) * $size - ( $size * 3 );
                my $sy = int( ( $cam->{y} - $h / 2 ) / $size ) * $size - ( $size * 3 );

                for ( my $i = $sx ; $i <= $w + $sx + ( $size * 6 ) ; $i += $size ) {
                    for ( my $j = $sy ; $j <= $h + $sy + ( $size * 6 ) ; $j += $size ) {
                        my $hash = mix( $STAR_SEED, $i, $j );
                        for ( 1 .. 2 ) {
                            my $px = $i + ( $hash % $size );
                            $hash >>= 3;
                            my $py = $j + ( $hash % $size );
                            $hash >>= 3;
                            my $color =
                              $py > $game_state->{ceiling} ? $c->{2} : $py < $game_state->{floor} ? $c->{3} : $c->{1};
                            $self->send_sprite_data(
                                location => [ ( $px - $cam->{x} ) / $self->w, ( $py - $cam->{y} ) / $self->h, ],
                                color    => $color,
                                rotation => 0,
                                scale    => 15,
                                texture  => "blob",
                            );
                        }
                    }
                }
            }

            for my $flier ( values %actors ) {
                $self->send_sprite_data(
                    location => [ ( $flier->{x} - $cam->{x} ) / $self->w, ( $flier->{y} - $cam->{y} ) / $self->h, ],
                    color => $c->{ $flier->{team} },
                    $flier->{is_bullet}
                    ? (
                        rotation => 0,
                        scale    => .3,
                        texture  => "bullet",
                      )
                    : (
                        rotation => $flier->{rot},
                        texture  => "player1",
                        scale    => 1.5,
                    )
                );
            }
        }
    );

    my @new_bullets = grep $_->{is_bullet}, map $actors{$_}, @{ $game_state->{new_actors} };
    $self->play_sound( "shot", $_, $cam, 3 ) for @new_bullets;

    my @dead_planes = grep !$_->{is_bullet}, @{ $game_state->{removed_actors} };
    $self->play_sound( "death", $_, $cam, 3 ) for @dead_planes;

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
    $self->print_text_2D( [ 0, $self->h - 12 ], "Controls: left up right d - Quit: q - Connect to server: n" );

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
    $self->print_text_2D( [ 0, 20 ], "FPS: " . $self->fps );
    $self->print_text_2D( [ 0, 10 ], "Frame: " . $self->frame );
    $self->print_text_2D( [], "Tick: " . $game_state->{tick} ) if $game_state->{tick};

    my $con = $self->console;
    my @to_display = grep defined, @{$con}[ max( 0, $#$con - 10 ) .. $#$con ];
    $self->print_text_2D( [ 0, $self->h - 22 - $_ * 10 ], $to_display[$_] ) for 0 .. $#to_display;

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
