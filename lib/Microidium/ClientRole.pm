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

1;

sub _build_pryo {
    my ( $self ) = @_;
    my $pryo = PryoNet::Client->new( client => shift );
    $pryo->add_listener(
        received => sub {
            my ( $connection, $frame ) = @_;
            $self->log( "got: " . ( ref $frame ? ( $frame->{tick} || "input" ) : $frame ) );
            if ( ref $frame and $frame->{tick} ) {
                $self->last_network_state( $frame );
            }
        }
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
    if ( my $tcp = $self->pryo->tcp ) {
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
    $self->pryo->connect( "127.0.0.1", 19366 ) if $sym == SDLK_n;
    if ( my $tcp = $self->pryo->tcp ) {
        $self->log( "sent: UP $sym" );
        $self->pryo->send_tcp( $self->client_state );
    }
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
    $self->draw_gfx_text( [ 0, 0 ], 0xff_ff_ff_ff, "Controls: left up right d - Quit: q - Connect to server: n" );
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

    my $con = $self->console;
    my @to_display = grep defined, @{$con}[ max( 0, $#$con - 10 ) .. $#$con ];
    $self->draw_gfx_text( [ 0, 8 + $_ * 8 ], 0xff_ff_ff_ff, $to_display[$_] ) for 0 .. $#to_display;

    return;
}

sub log { push @{ shift->console }, @_ }
