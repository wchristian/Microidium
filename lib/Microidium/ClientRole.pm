package Microidium::ClientRole;

use strictures;

# VERSION

use lib '..';
use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d n o l );
use List::Util qw( min max );
use Carp::Always;
use Microidium::Helpers 'dfile';
use PryoNet::Client;
use Acme::MITHALDU::XSGrabBag 'mix';
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
my @explosions;

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
            if ( $frame->isa( "Microidium::Gamestate" ) ) {
                my $game_state = $self->game_state;
                return if $frame->{tick} < $game_state->{tick};
                $self->last_network_state( $frame );
            }
            elsif ( $frame->isa( "Microidium::GiveConnectionId" ) ) {
                $self->log( "got network id: $frame->{network_player_id}" );
                $self->network_player_id( $frame->{network_player_id} );
            }
            else {
                die "received unknown frame: " . ref $frame;
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
        $self->pryo->send_tcp( bless $self->client_state, "Microidium::Clientstate" );
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
    $self->pryo->connect( 5, "127.0.0.1", 19366, 19366 );
    return;
}

sub render_world {
    my ( $self, $game_state ) = @_;

    if ( !$self->music_is_playing ) {
        my $music = SDL::Mixer::Music::load_MUS( dfile 'vecinec22.ogg' );
        SDL::Mixer::Music::volume_music( 30 );
        die "music playback error" if SDL::Mixer::Music::play_music( $music, -1 ) == -1;
        $self->music_is_playing( 1 );
    }

    $self->update_camera( $game_state );

    my $cam = $self->client_state->{camera};

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

            @sprites = sort { $b->[0][2] <=> $a->[0][2] } @sprites;

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
                    {
                        my @color = @{ $c->{ $flier->{team} } };
                        if (   $flier->{y} < $self->game_state->{floor}
                            or $flier->{y} > $self->game_state->{ceiling} )
                        {
                            $color[$_] *= 0.5 for 0 .. 2;
                        }
                        push @sprites,
                          [ [ $flier->{x}, $flier->{y}, ], \@color, $flier->{rot}, 1.5, "player1_wings", 1 ];
                    }
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
                    push @sprites, [ [ $flier->{x}, $flier->{y}, ], \@color, $flier->{rot}, 1.5, $flames{$_}, 1 ]
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

            @explosions = grep $_->{life} > 0, @explosions;
            for my $event ( @{ $game_state->{events} } ) {
                next if $event->{type} ne "flier_died";
                my $scale = $event->{is_bullet} ? 0.3 : 1;
                my $life  = $event->{is_bullet} ? 1   : 1.5;
                push @explosions,
                  { x => $event->{x}, y => $event->{y}, life => $life, scale => $scale, team => $event->{team} };
            }

            for my $ex ( @explosions ) {
                my @color = ( @{ $c->{ $ex->{team} } }[ 0 .. 2 ], 0.8 * $ex->{life} );
                my $scale = $ex->{scale} * $ex->{life};
                push @sprites, [ [ $ex->{x}, $ex->{y} ], \@color, 0, $scale, "bullet" ];
                $ex->{life} -= 0.1;
            }

            push $self->timestamps, [ sprite_prepare_end => time ];
            $self->send_sprite_datas( @sprites );
            push $self->timestamps, [ sprite_send_end => time ];
        }
    );
    push $self->timestamps, [ sprite_render_end => time ];

    my $player_actor = $self->local_player_actor;
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
    my $distance = sqrt( ( $x_diff )**2 + ( $flier->{y} - $cam->{y} )**2 );
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

    $self->print_text_2D( [ 0, 90 ], "Perl v$]" );

    $self->print_text_2D(
        [ 0, 80 ],
        sprintf
          "Viewport: %d x %d = %.2f MPix",
        $self->width, $self->height, $self->width * $self->height / 1_000_000

    );

    $self->print_text_2D(
        [ 0, 70 ],
        sprintf "Render: %d x %d = %.2f MPix",
        $self->aspect_ratio * $self->fb_height,
        $self->fb_height, $self->aspect_ratio * $self->fb_height * $self->fb_height / 1_000_000
    );

    $self->print_text_2D( [ 0, 60 ], sprintf "Sprites: %d", $self->sprite_count );

    $self->print_text_2D( [ 0, 50 ],
        sprintf( "Audio channels:|%s|", join "", map { SDL::Mixer::Channels::playing( $_ ) ? 'x' : ' ' } 0 .. 31 ) );
    if ( $player_actor ) {
        $self->print_text_2D( [ 0, 40 ], "HP: $player_actor->{hp}" );
        $self->print_text_2D(
            [ 0, 30 ],
            sprintf "X: % 8.2f / Y: % 8.2f / R: % 8.2f / Speed: % 8.2f",
            ( map $player_actor->{$_}, qw( x y rot ) ),
            sqrt( $player_actor->{x_speed}**2 + $player_actor->{y_speed}**2 )
        );
    }
    $self->print_text_2D( [ 0, 20 ], sprintf "FPS: %5.1f", 1 / $self->frame_time );
    my $tick = $game_state->{tick} || 0;
    $self->print_text_2D( [ 0, 10 ],
        sprintf( "Frame: %d / Tick: %d / Dropped: %d", $self->frame, $tick, $tick - $self->frame ) );

    my $con = $self->console;
    my @to_display = grep defined, @{$con}[ max( 0, $#$con - 10 ) .. $#$con ];
    $self->print_text_2D( [ 0, $self->height - 22 - $_ * 10 ], $to_display[$_] ) for 0 .. $#to_display;

    my %timing_types  = $self->timing_types;
    my @timing_colors = $self->timing_colors;
    my $y             = 0;
    my $x             = 70 + $self->width / 2;
    my @used          = grep $self->used_timing_types->{$_}, keys %timing_types;

    for my $timing ( sort { $timing_types{$a} <=> $timing_types{$b} } @used ) {
        $self->print_text_2D( [ $x, $y, undef, $timing_colors[ $timing_types{$timing} ] ], $timing );
        $y += 12;
    }

    return;
}

# see bin/generate_colors
sub timing_colors {
    (
        [ 1.0,               0.0,               0.0,               0.85 ],
        [ 0.690196078431373, 1.0,               0.43921568627451,  0.85 ],
        [ 0.650980392156863, 0.0,               1.0,               0.85 ],
        [ 1.0,               0.219607843137255, 0.219607843137255, 0.85 ],
        [ 0.0,               1.0,               0.584313725490196, 0.85 ],
        [ 0.803921568627451, 0.43921568627451,  1.0,               0.85 ],
        [ 1.0,               0.43921568627451,  0.43921568627451,  0.85 ],
        [ 0.43921568627451,  1.0,               0.764705882352941, 0.85 ],
        [ 1.0,               0.0,               0.831372549019608, 0.85 ],
        [ 1.0,               0.517647058823529, 0.0,               0.85 ],
        [ 0.0,               0.901960784313726, 1.0,               0.85 ],
        [ 1.0,               0.43921568627451,  0.905882352941176, 0.85 ],
        [ 1.0,               0.729411764705882, 0.43921568627451,  0.85 ],
        [ 0.0,               0.384313725490196, 1.0,               0.85 ],
        [ 1.0,               0.0,               0.317647058823529, 0.85 ],
        [ 0.964705882352941, 1.0,               0.0,               0.85 ],
        [ 0.219607843137255, 0.517647058823529, 1.0,               0.85 ],
        [ 1.0,               0.219607843137255, 0.466666666666667, 0.85 ],
        [ 0.980392156862745, 1.0,               0.43921568627451,  0.85 ],
        [ 0.43921568627451,  0.654901960784314, 1.0,               0.85 ],
        [ 1.0,               0.43921568627451,  0.615686274509804, 0.85 ],
        [ 0.450980392156863, 1.0,               0.0,               0.85 ],
        [ 0.133333333333333, 0.0,               1.0,               0.85 ],
    );
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
