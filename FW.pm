package FW;

use SDL            ();
use SDLx::App      ();
use SDL::Constants ();
use SDL::GFX::Rotozoom 'SMOOTHING_OFF';
use Time::HiRes 'time';
use curry;
use Clone 'clone';

use Moo::Role;

has app => ( is => 'rw', builder => 1, handles => [qw( run stop w h draw_rect draw_gfx_text flip blit_by )] );

has frame              => ( is => 'rw', default => sub { 0 } );
has last_frame_time    => ( is => 'rw', default => sub { time } );
has current_frame_time => ( is => 'rw', default => sub { time } );

has event_handlers => ( is => 'rw', builder => 1 );
has game_state     => ( is => 'rw', builder => 1 );
has client_state   => ( is => 'rw', builder => 1 );
has world_display  => ( is => 'rw', builder => 1 );

1;

sub _build_app {
    my ( $self ) = @_;
    return SDLx::App->new(
        event_handlers => [ $self->curry::on_event ],
        move_handlers  => [ $self->curry::on_move ],
        show_handlers  => [ $self->curry::on_show ],
    );
}

sub _build_event_handlers {
    my ( $self ) = @_;
    my %handlers = map { SDL::Constants->${ \"SDL_$_" } => $self->can( "on_" . lc $_ ) } qw(
      ACTIVEEVENT   USEREVENT       SYSWMEVENT    KEYDOWN       KEYUP
      MOUSEMOTION   MOUSEBUTTONDOWN MOUSEBUTTONUP
      JOYAXISMOTION JOYBALLMOTION   JOYHATMOTION  JOYBUTTONDOWN JOYBUTTONUP
      VIDEORESIZE   VIDEOEXPOSE     QUIT
    );
    return \%handlers;
}

sub _build_world_display {
    my ( $self ) = @_;
    my $zoom = $self->zoom;
    return { surface => $self->temp_surface( width => $self->w / $zoom, height => $self->h / $zoom ) };
}

sub zoom { shift->client_state->{zoom} || 1 }

sub on_event {
    my ( $self, $event ) = @_;
    my $type     = $event->type;
    my $handlers = $self->event_handlers;
    die "unknown event type: $type" if !exists $handlers->{$type};
    return unless my $meth = $handlers->{$type};
    $self->$meth( $event );
    return;
}

sub on_move {
    my ( $self ) = @_;
    my $new_game_state = clone $self->game_state;
    $self->update_game_state( $self->game_state, $new_game_state, $self->client_state );
    $self->game_state( $new_game_state );
    return;
}

sub on_show {
    my ( $self ) = @_;
    $self->frame( $self->frame + 1 );
    $self->last_frame_time( $self->current_frame_time );
    $self->current_frame_time( time );
    $self->render;
    $self->flip;
    return;
}

sub render {
    my ( $self ) = @_;

    my $world      = $self->world_display->{surface};
    my $game_state = $self->game_state;
    my $zoom       = $self->zoom;

    $self->clear_surface( $world, 0x330000ff );
    $self->render_world( $world, $game_state );
    $self->blit_by( SDL::GFX::Rotozoom::surface_xy( $world, 180, -$zoom, $zoom, SMOOTHING_OFF ) );
    $self->render_ui( $game_state );

    return;
}

sub clear_surface {
    my ( $self, $surface, $color ) = @_;
    $surface->draw_rect( undef, $color );
    return;
}

sub fps {
    my ( $self ) = @_;
    my $elapsed = $self->current_frame_time - $self->last_frame_time;
    return 999 if !$elapsed;
    return 1 / $elapsed;
}

sub temp_surface {
    shift;
    SDLx::Surface->new( surface => SDL::Video::display_format( SDLx::Surface->new( @_ ) ) );
}
