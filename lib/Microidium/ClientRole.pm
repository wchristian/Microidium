package Microidium::ClientRole;

# VERSION

use lib '..';
use 5.010;
use SDL::Constants map "SDLK_$_", qw( q UP LEFT RIGHT d n );
use Math::Trig qw' deg2rad rad2deg ';
use SDLx::Sprite;
use Math::Vec qw(NewVec);
use List::Util qw( first min max );
use Carp::Always;
use curry;
use Microidium::Helpers 'dfile';
use PryoNet::Client;

use Moo::Role;

requires "update_game_state";

has sounds => (
    is      => 'lazy',
    builder => sub {
        my %sounds = map { $_ => SDL::Mixer::Samples::load_WAV( dfile "$_.wav" ) } qw( shot death );
        return \%sounds;
    }
);
has player_sprites => (
    is      => 'ro',
    default => sub {
        return { map { $_ => SDLx::Sprite->new( image => dfile "player$_.png" ) } 1 .. 3, };
    }
);
has bullet_sprite => ( is => 'ro', default => sub { SDLx::Sprite->new( image => dfile "bullet.png" ) } );
has pryo => ( is => 'lazy', builder => 1 );
has console => ( is => 'ro', default => sub { [ time, qw( a b c ) ] } );
has last_network_state => ( is => 'rw' );
around update_game_state => \&client_update_game_state;
has last_player_hit      => ( is => 'rw', default => sub { 0 } );
after update_game_state  => \&update_last_player_hit;
has in_network_game   => ( is => 'rw' );
has local_player_id   => ( is => 'rw' );
has network_player_id => ( is => 'rw' );

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
        zoom       => 1,
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

sub render_world {
    my ( $self, $world, $game_state ) = @_;
    my $player_actor = $self->local_player_actor;
    my $cam          = $self->client_state->{camera};
    @{$cam}{qw(x y)} = @{$player_actor}{qw(x y)} if $player_actor;

    if ( defined $game_state->{ceiling}
        and ( my $ceil_height = $world->h / 2 - $cam->{y} + $game_state->{ceiling} ) >= 0 )
    {
        $world->draw_rect( [ 0, 0, $world->w, $ceil_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $ceil_height ], [ $world->w, $ceil_height ], 0xff_ff_ff_ff, 0 );
    }

    if ( defined $game_state->{floor}
        and ( my $floor_height = $world->h / 2 - $cam->{y} + $game_state->{floor} ) <= $world->h )
    {
        $world->draw_rect( [ 0, $floor_height, $world->w, $world->h - $floor_height ], 0xff_30_30_ff );
        $world->draw_line( [ 0, $floor_height ], [ $world->w, $floor_height ], 0xff_ff_ff_ff, 0 );
    }

    my $highlight = ( $self->last_player_hit > time - 2 );
    my $stall_color = $highlight ? 0xff_ff_ff_88 : 0xff_ff_ff_44;
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
    my %actors        = %{ $game_state->{actors} };
    for my $flier ( values %actors ) {
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
    SDL::Mixer::Effects::set_position( $channel, $angle, $distance );
    return;
}

sub render_ui {
    my ( $self, $game_state ) = @_;
    my $player_actor = $self->local_player_actor;
    $self->draw_gfx_text( [ 0, 0 ], 0xff_ff_ff_ff, "Controls: left up right d - Quit: q - Connect to server: n" );
    $self->draw_gfx_text(
        [ 0, $self->h - 48 ],
        0xff_ff_ff_ff, sprintf "Audio channels:|%s|",
        join "", map { SDL::Mixer::Channels::playing( $_ ) ? 'x' : ' ' } 0 .. 31
    );
    $self->draw_gfx_text( [ 0, $self->h - 40 ], 0xff_ff_ff_ff, "HP: $player_actor->{hp}" ) if $player_actor;
    $self->draw_gfx_text(
        [ 0, $self->h - 32 ],
        0xff_ff_ff_ff, join ' ',
        ( map $player_actor->{$_}, qw( x y rot ) ),
        ( $player_actor->{x_speed}**2 + $player_actor->{y_speed}**2 )**0.5
    ) if $player_actor;
    $self->draw_gfx_text( [ 0, $self->h - 24 ], 0xff_ff_ff_ff, $self->fps );
    $self->draw_gfx_text( [ 0, $self->h - 16 ], 0xff_ff_ff_ff, $self->frame );
    $self->draw_gfx_text( [ 0, $self->h - 8 ],  0xff_ff_ff_ff, $game_state->{tick} ) if $game_state->{tick};

    my $con = $self->console;
    my @to_display = grep defined, @{$con}[ max( 0, $#$con - 10 ) .. $#$con ];
    $self->draw_gfx_text( [ 0, 8 + $_ * 8 ], 0xff_ff_ff_ff, $to_display[$_] ) for 0 .. $#to_display;

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
