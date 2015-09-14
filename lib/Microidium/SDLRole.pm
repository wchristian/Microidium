package Microidium::SDLRole;

use strictures;

# VERSION

use 5.010;

use Alien::SDL 1.446 ();
use SDL                  ();
use SDLx::App            ();
use SDL::Constants       ();
use SDL::Mixer::Samples  ();
use SDL::Mixer::Channels ();
use SDL::Mixer::Effects  ();
use SDL::Mixer::Music    ();
use SDL::Mixer;
use Time::HiRes 'time';
use curry;
use Clone 'clone';
use Acme::MITHALDU::BleedingOpenGL ':functions';
use IO::All -binary;
use OpenGL::Image;
use Carp 'confess';
use List::Util 'min';
use Color::Mix;
use Microidium::Helpers 'dfile';

use Moo::Role;

use experimental 'autoderef';

has app => ( is => 'lazy', handles => [qw( run stop sync )] );

has display_scale   => ( is => 'rw', default => sub { 600 } );
has width           => ( is => 'rw', default => sub { 800 } );
has height          => ( is => 'rw', default => sub { 600 } );
has fb_height       => ( is => 'rw', default => sub { 600 } );
has fb_height_max   => ( is => 'rw', default => sub { 600 } );
has sprite_size     => ( is => 'rw', default => sub { 160 } );
has fov             => ( is => 'rw', default => sub { 90 } );
has frame           => ( is => 'rw', default => sub { 0 } );
has fps             => ( is => 'rw', default => sub { 0 } );
has frame_time      => ( is => 'rw', default => sub { 0 } );
has last_frame_time => ( is => 'rw', default => sub { time } );
has frame_calc_time => ( is => 'rw', default => sub { 0 } );
has fps_aim         => ( is => 'rw', default => sub { 62 } );

has $_ => ( is => 'rw', builder => 1 ) for qw( event_handlers game_state client_state );

has game_state_history => ( is => 'rw', default => sub { [] } );
has max_history        => ( is => 'rw', default => sub { 10 } );

has $_ => ( is => 'ro', default => sub { {} } ) for qw( textures shaders uniforms attribs vbos vaos );
has sprites          => ( is => 'rw', default => sub { {} } );
has sprite_count     => ( is => 'rw', default => sub { 0 } );
has sprite_tex_order => ( is => 'rw', default => sub { [] } );
has fbos             => ( is => 'rw', default => sub { {} } );

has timings_max         => ( is => 'rw', default => sub { 18 } );
has timings_max_frames  => ( is => 'rw', default => sub { 180 } );
has timings             => ( is => 'lazy' );
has previous_timestamps => ( is => 'rw', default => sub { [] } );
has timestamps          => ( is => 'rw', default => sub { [] } );
has used_timing_types   => ( is => 'rw', default => sub { {} } );
has timing_types        => ( is => 'lazy' );

sub _build_timings {
    my ( $self ) = @_;
    return {
        list => [ map { $_, ( 0, 0 ) x $self->timings_max } 0 .. $self->timings_max_frames - 1 ],
        pointer => 0,
    };
}

BEGIN {
    my %gl_constants = map { $_ => 1 } qw(
      GL_TEXTURE_2D GL_FLOAT GL_FALSE GL_TRIANGLES GL_COLOR_BUFFER_BIT
      GL_TEXTURE0 GL_ARRAY_BUFFER GL_BLEND GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
      GL_STATIC_DRAW GL_TEXTURE_MIN_FILTER GL_ONE GL_CLAMP GL_LINEAR
      GL_TEXTURE_MAG_FILTER GL_NEAREST GL_VERTEX_SHADER GL_FRAGMENT_SHADER
      GL_COMPILE_STATUS GL_LINK_STATUS GL_GEOMETRY_SHADER GL_POINTS
      GL_TEXTURE_WRAP_S  GL_TEXTURE_WRAP_T GL_RGBA GL_DEPTH_COMPONENT
      GL_FRAMEBUFFER GL_DRAW_FRAMEBUFFER GL_FRAMEBUFFER_COMPLETE
      GL_COLOR_ATTACHMENT0_EXT GL_DEPTH_ATTACHMENT GL_STREAM_DRAW GL_VERSION
      GL_RENDERER
    );

    for my $name ( keys %gl_constants ) {
        my $val = eval "Acme::MITHALDU::BleedingOpenGL::$name()";
        die $@ if $@;
        eval "sub $name () { $val }";
        die $@ if $@;
    }
}

1;

sub _build_app {
    my ( $self ) = @_;

    # i'd use mp3, but throwing mp3 at the music mixer seems to crash it
    die "no ogg support" if !( SDL::Mixer::init( MIX_INIT_OGG ) & MIX_INIT_OGG );

    printf "Error initializing SDL_mixer: %s\n", SDL::get_error
      if SDL::Mixer::open_audio 44100, AUDIO_S16, 2, 1024;
    SDL::Mixer::Channels::allocate_channels 32;

    my $app = SDLx::App->new(
        event_handlers => [ $self->curry::on_event ],
        move_handlers  => [ $self->curry::on_move ],
        show_handlers  => [ $self->curry::on_show ],
        gl             => 1,
        width          => $self->width,
        height         => $self->height,
        resizeable     => 1,
        min_t          => 1 / $self->fps_aim,
    );

    say glGetString GL_RENDERER;
    my $version = glGetString GL_VERSION;
    $version =~ s/ .*//;
    $version = version->parse( $version );
    die "Your OpenGL version is $version. You must have at least OpenGL 3.3 to run this tutorial.\n"
      if $version < 3.003;

    $self->init_sprites;
    $self->init_text_2D( dfile "courier.tga" );
    $self->init_screen_target;
    $self->init_post_process;
    $self->init_timings;

    return $app;
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

sub on_event {
    my ( $self, $event ) = @_;
    push $self->timestamps, [ event_start => time ];
    my $type     = $event->type;
    my $handlers = $self->event_handlers;
    die "unknown event type: $type" if !exists $handlers->{$type};
    my $meth = $handlers->{$type};
    $self->$meth( $event ) if $meth;
    push $self->timestamps, [ event_end => time ];
    return;
}

sub aspect_ratio { my $self = shift; $self->width / $self->height }

sub on_videoresize {
    my ( $self, $event ) = @_;

    $self->width( $event->resize_w );
    $self->height( $event->resize_h );

    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{aspect_ratio}, $self->aspect_ratio;

    glUseProgramObjectARB $self->shaders->{post_process};
    glUniform1fARB $self->uniforms->{post_process}{aspect_ratio}, $self->aspect_ratio;

    glUseProgramObjectARB $self->shaders->{text};
    glUniform2fARB $self->uniforms->{text}{screen}, $self->width, $self->height;

    glUseProgramObjectARB $self->shaders->{timings};
    glUniform1fARB $self->uniforms->{timings}{pixel_width},  2 / $self->width;
    glUniform1fARB $self->uniforms->{timings}{pixel_height}, 2 / $self->height;

    $self->fb_height( min( $self->fb_height_max, $self->height ) );
    $self->init_fbo( $_ ) for qw( screen_target post_process );

    return;
}

sub change_fov {
    my ( $self, $fov ) = @_;
    $self->fov( $fov );
    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{fov}, $self->fov;
    return;
}

sub historize {
    my ( $self, $new, $type ) = @_;
    my $old = $self->$type;
    return if $new->{tick} == $old->{tick};
    my $h_meth  = $type . "_history";
    my $history = $self->$h_meth;
    push @{$history}, $old;
    shift @{$history} while @{$history} > $self->max_history;
    $self->$type( $new );
    return;
}

sub on_move {
    my ( $self ) = @_;
    push $self->timestamps, [ move_start => time ];
    $self->finalize_frame_timings;
    my $new_game_state = clone $self->game_state;
    $self->update_game_state( $new_game_state, $self->client_state );
    $self->historize( $new_game_state, "game_state" );
    push $self->timestamps, [ move_end => time ];
    return;
}

sub on_show {
    my ( $self ) = @_;

    my $now = time;
    push $self->timestamps, [ frame_start => $now ];
    $self->smooth_update( frame_time => $now - $self->last_frame_time );
    $self->last_frame_time( $now );
    $self->frame( $self->frame + 1 );

    $self->render;
    $self->render_timings;

    SDL::Video::GL_swap_buffers;
    my $end = time;
    push $self->timestamps, [ sync_end => $end ];
    $self->smooth_update( frame_calc_time => $end - $now, 0.02 );

    return;
}

sub finalize_frame_timings {
    my ( $self ) = @_;

    my $pointer = $self->timings->{pointer};
    $pointer++;
    $self->timings->{pointer} = $pointer >= $self->timings_max_frames ? $pointer - $self->timings_max_frames : $pointer;
    $self->previous_timestamps( $self->timestamps );
    $self->timestamps( [ $self->timestamps->[-1] ] );

    return;
}

sub clone_client_game_state {
    my $cgs = shift->client_game_state;
    my $bak = delete $cgs->{trails};
    my $new = clone $cgs;
    $cgs->{trails} = $bak;
    %{ $new->{trails} } = %{$bak};
    return $new;
}

sub synch_client_game_state {
    my ( $self ) = @_;

    my $game_state = $self->game_state;
    my $game_id    = $game_state->{id};

    $self->client_game_state( $self->_build_client_game_state ) if $self->client_game_state->{id} ne $game_id;

    my $cgs_tick = $self->client_game_state->{tick};

    my @candidates = grep $cgs_tick < $_->{tick} && $game_id eq $_->{id},
      @{ $self->game_state_history }, $self->game_state;
    @candidates = sort { $a <=> $b } @candidates;

    while ( @candidates and $self->client_game_state->{tick} < $game_state->{tick} ) {
        my $game_state            = shift @candidates;
        my $new_client_game_state = $self->clone_client_game_state;
        $self->update_client_game_state( $game_state, $new_client_game_state );
        $self->historize( $new_client_game_state, "client_game_state" );
    }

    return;
}

sub render {
    my ( $self ) = @_;

    $self->synch_client_game_state;
    my $game_state = $self->game_state;

    glBindFramebufferEXT GL_DRAW_FRAMEBUFFER, $self->fbos->{post_process};
    glViewport( 0, 0, $self->fb_height * $self->aspect_ratio, $self->fb_height );
    glClearColor 0.3, 0, 0, 1;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_world( $game_state, $self->client_game_state );
    push $self->timestamps, [ world_render_end => time ];

    glBindFramebufferEXT GL_DRAW_FRAMEBUFFER, $self->fbos->{screen_target};
    glViewport( 0, 0, $self->fb_height * $self->aspect_ratio, $self->fb_height );
    glClearColor 0.0, 0, 0, 0;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_post_process;
    push $self->timestamps, [ postprocess_render_end => time ];

    glBindFramebufferEXT GL_FRAMEBUFFER, 0;    # screen
    glViewport( 0, 0, $self->width, $self->height );
    glClearColor 0, 0, 0, 0;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_screen_target;
    push $self->timestamps, [ screen_render_end => time ];

    $self->render_ui( $game_state, $self->client_game_state );
    push $self->timestamps, [ ui_render_end => time ];

    return;
}

sub smooth_update {
    my ( $self, $attrib, $new, $factor ) = @_;
    my $old  = $self->$attrib;
    my $diff = $new - $old;
    $self->$attrib( $old + $diff * ( $factor || .08 ) );
    return;
}

sub glGetAttribLocationARB_p_safe {
    my ( $self, $shader_name, $attrib_name ) = @_;
    my $shader = $self->shaders->{$shader_name};
    my $ret = glGetAttribLocationARB_p $shader, $attrib_name;
    die "Could not find attribute '$attrib_name' in '$shader_name'" if $ret == -1;
    return $ret;
}

sub glGetUniformLocationARB_p_safe {
    my ( $self, $shader_name, $attrib_name ) = @_;
    my $shader = $self->shaders->{$shader_name};
    my $ret = glGetUniformLocationARB_p $shader, $attrib_name;
    die "Could not find uniform '$attrib_name' in '$shader_name'" if $ret == -1;
    return $ret;
}

sub init_fbo {
    my ( $self, $name ) = @_;

    my @dim = ( $self->fb_height * $self->aspect_ratio, $self->fb_height );
    my $textures = $self->textures;

    # color texture
    my $color = $textures->{"fbo_color_$name"} = glGenTextures_p 1;
    glBindTexture GL_TEXTURE_2D,   $color;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP;
    glTexImage2D_c GL_TEXTURE_2D,  0, GL_RGBA, @dim, 0, GL_RGBA, GL_FLOAT, 0;

    # depth texture
    my $depth = $textures->{"fbo_depth_$name"} = glGenTextures_p 1;
    glBindTexture GL_TEXTURE_2D,   $depth;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP;
    glTexImage2D_c GL_TEXTURE_2D,  0, GL_DEPTH_COMPONENT, @dim, 0, GL_DEPTH_COMPONENT, GL_FLOAT, 0;

    # fbo
    $self->fbos->{$name} = glGenFramebuffersEXT_p 1;
    glBindFramebufferEXT GL_FRAMEBUFFER, $self->fbos->{$name};

    # attach textures to fbo
    glFramebufferTexture2DEXT GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, $color, 0;
    glFramebufferTexture2DEXT GL_DRAW_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,      GL_TEXTURE_2D, $depth, 0;

    my $Status = glCheckFramebufferStatusEXT GL_FRAMEBUFFER;
    die "FB error, status: 0x%x\n", $Status if $Status != GL_FRAMEBUFFER_COMPLETE;

    return;
}

sub init_post_process {
    my ( $self ) = @_;

    $self->init_fbo( "post_process" );

    $self->shaders->{post_process} = $self->load_shader_set( map dfile "post_process.$_", qw( vert frag geom ) );
    $self->uniforms->{post_process}{$_} = $self->glGetUniformLocationARB_p_safe( "post_process", $_ )
      for qw( texture display_scale aspect_ratio );

    glUseProgramObjectARB $self->shaders->{post_process};
    glUniform1fARB $self->uniforms->{post_process}{display_scale}, $self->display_scale;
    glUniform1fARB $self->uniforms->{post_process}{aspect_ratio},  $self->aspect_ratio;
    glUniform1iARB $self->uniforms->{post_process}{texture},       0;

    return;
}

sub init_screen_target {
    my ( $self ) = @_;

    $self->init_fbo( "screen_target" );

    $self->shaders->{screen_target} = $self->load_shader_set( map dfile "screen_target.$_", qw( vert frag geom ) );
    $self->uniforms->{screen_target}{$_} = $self->glGetUniformLocationARB_p_safe( "screen_target", $_ )
      for qw( texture   );

    glUseProgramObjectARB $self->shaders->{screen_target};
    glUniform1iARB $self->uniforms->{screen_target}{texture}, 0;

    return;
}

# TODO: see https://github.com/nikki93/opengl/blob/master/main.cpp
sub init_sprites {
    my ( $self ) = @_;

    $self->new_vbo( $_ ) for qw( sprite );
    $self->new_vao( $_ ) for qw( sprite );

    $self->shaders->{sprites} = $self->load_shader_set( map dfile "sprite.$_", qw( vert frag geom ) );
    $self->uniforms->{sprites}{$_} = $self->glGetUniformLocationARB_p_safe( "sprites", $_ )
      for qw( texture camera display_scale aspect_ratio sprite_size fov );
    $self->attribs->{sprites}{$_} = $self->glGetAttribLocationARB_p_safe( "sprites", $_ )
      for qw( color offset rotation scale r_scale );

    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{display_scale}, $self->display_scale;
    glUniform1fARB $self->uniforms->{sprites}{aspect_ratio},  $self->aspect_ratio;
    glUniform1fARB $self->uniforms->{sprites}{sprite_size},   $self->sprite_size;
    glUniform1fARB $self->uniforms->{sprites}{fov},           $self->fov;

    $self->sprite_tex_order(
        [qw( blob thrust_flame thrust_right_flame thrust_left_flame player1_wings player1 bullet )] );
    $self->textures->{$_} = $self->load_texture( dfile "$_.tga" ) for @{ $self->sprite_tex_order };

    glBindVertexArray $self->vaos->{sprite};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{sprite};

    my $attribs = $self->attribs->{sprites};

    glEnableVertexAttribArrayARB $attribs->{color};
    glEnableVertexAttribArrayARB $attribs->{offset};
    glEnableVertexAttribArrayARB $attribs->{rotation};
    glEnableVertexAttribArrayARB $attribs->{scale};
    glEnableVertexAttribArrayARB $attribs->{r_scale};

    my $value_count = 3 + 4 + 1 + 1 + 1;
    my $stride      = 4 * $value_count;    # bytes * counts
    glVertexAttribPointerARB_c $attribs->{offset},   3, GL_FLOAT, GL_FALSE, $stride, ( 0 ) * 4;
    glVertexAttribPointerARB_c $attribs->{color},    4, GL_FLOAT, GL_FALSE, $stride, ( 3 ) * 4;
    glVertexAttribPointerARB_c $attribs->{rotation}, 1, GL_FLOAT, GL_FALSE, $stride, ( 3 + 4 ) * 4;
    glVertexAttribPointerARB_c $attribs->{scale},    1, GL_FLOAT, GL_FALSE, $stride, ( 3 + 4 + 1 ) * 4;
    glVertexAttribPointerARB_c $attribs->{r_scale},  1, GL_FLOAT, GL_FALSE, $stride, ( 3 + 4 + 1 + 1 ) * 4;

    glBindVertexArray 0;

    return;
}

sub init_text_2D {
    my ( $self, $path ) = @_;

    $self->new_vbo( $_ ) for qw( text_vertices );
    $self->new_vao( $_ ) for qw( text_vertices );

    $self->shaders->{text} = $self->load_shader_set( map dfile "text.$_", qw( vert frag geom ) );
    $self->uniforms->{text}{$_} = $self->glGetUniformLocationARB_p_safe( "text", $_ )
      for qw( texture color screen size );
    $self->attribs->{text}{$_} = $self->glGetAttribLocationARB_p_safe( "text", $_ ) for qw( vertex );

    glUseProgramObjectARB $self->shaders->{text};
    glUniform2fARB $self->uniforms->{text}{screen}, $self->width, $self->height;
    glUniform1iARB $self->uniforms->{text}{texture}, 0;

    $self->textures->{text} = $self->load_texture( $path );

    glBindVertexArray $self->vaos->{text_vertices};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{text_vertices};

    my $attribs = $self->attribs->{text};

    glEnableVertexAttribArrayARB $attribs->{vertex};

    glVertexAttribPointerARB_c $attribs->{vertex}, 3, GL_FLOAT, GL_FALSE, 0, 0;

    glBindVertexArray 0;

    return;
}

sub init_timings {
    my ( $self ) = @_;

    $self->new_vbo( $_ ) for qw( timings );
    $self->new_vao( $_ ) for qw( timings );

    $self->shaders->{timings} = $self->load_shader_set( map dfile "timings.$_", qw( vert frag geom ) );
    $self->uniforms->{timings}{$_} = $self->glGetUniformLocationARB_p_safe( "timings", $_ )
      for qw( timings_max_frames pixel_width pixel_height pointer );
    $self->attribs->{timings}{$_} = $self->glGetAttribLocationARB_p_safe( "timings", $_ )
      for qw( index ), map "times$_", 1 .. $self->timings_max / 2;

    glUseProgramObjectARB $self->shaders->{timings};
    glUniform1fARB $self->uniforms->{timings}{timings_max_frames}, $self->timings_max_frames;
    glUniform1fARB $self->uniforms->{timings}{pixel_width},        2 / $self->width;
    glUniform1fARB $self->uniforms->{timings}{pixel_height},       2 / $self->height;

    glBindVertexArray $self->vaos->{timings};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{timings};

    my $attribs = $self->attribs->{timings};
    glEnableVertexAttribArrayARB $attribs->{index};
    glEnableVertexAttribArrayARB $attribs->{$_} for map "times$_", 1 .. $self->timings_max / 2;

    my $value_count = 1 + ( 4 * $self->timings_max / 2 );
    my $stride = 4 * $value_count;    # bytes * counts
    glVertexAttribPointerARB_c $attribs->{index}, 1, GL_FLOAT, GL_FALSE, $stride, 0;
    glVertexAttribPointerARB_c $attribs->{"times$_"}, 4, GL_FLOAT, GL_FALSE, $stride, ( 1 + ( 4 * ( $_ - 1 ) ) ) * 4
      for 1 .. $self->timings_max / 2;

    return;
}

sub _build_timing_types {
    my @types = qw(
      event_end__frame_start
      move_start__move_end
      move_end__move_start
      move_end__frame_start
      frame_start__integrate_end
      frame_start__sprite_prepare_end
      integrate_end__sprite_prepare_end
      sprite_prepare_end__sprite_send_end
      sprite_send_end__sprite_render_end
      sprite_render_end__world_render_end
      world_render_end__postprocess_render_end
      postprocess_render_end__screen_render_end
      screen_render_end__ui_render_end
      ui_render_end__timings_render_start
      timings_render_start__timings_render_end
      timings_render_end__sync_end
      event_start__event_end
      event_end__event_start
      sync_end__event_start
      sync_end__move_start
    );
    my %types = map { $types[$_] => $_ } 0 .. $#types;
    $types{event_end__move_start} = $types{sync_end__move_start};
    return \%types;
}

sub render_timings {
    my ( $self ) = @_;

    push $self->timestamps, [ timings_render_start => time ];
    my @time_stamps  = @{ $self->previous_timestamps };
    my %timing_types = %{ $self->timing_types };
    my $elapse_limit = 0.0001;
    my @current_timings;
    for my $i ( 1 .. $#time_stamps ) {
        my $end = $time_stamps[$i];
        if ( $end ) {
            my $start     = $time_stamps[ $i - 1 ];
            my $type_name = "$start->[0]__$end->[0]";
            my $type      = $timing_types{$type_name} // die "unknown type_name: $type_name";
            my $elapsed   = $end->[1] - $start->[1];
            $self->used_timing_types->{$type_name} = 1 if $elapsed > $elapse_limit;
            if (
                @current_timings
                and (
                    $type == $current_timings[-1]
                    or (    $current_timings[-1] == $timing_types{event_start__event_end}
                        and $type == $timing_types{event_end__event_start} )
                    or (    $current_timings[-1] == $timing_types{move_start__move_end}
                        and $type == $timing_types{move_end__move_start} )
                )
              )
            {
                $current_timings[-2] += $elapsed;
                $self->used_timing_types->{$type_name} = 1 if $current_timings[-2] > $elapse_limit;
            }
            else {
                push @current_timings, $elapsed, $type;
            }
        }
    }
    if ( @current_timings > 2 * $self->timings_max ) {
        die "too many timings";
    }
    while ( @current_timings < 2 * $self->timings_max ) {
        push @current_timings, 0, 0;
    }

    my $pointer = $self->timings->{pointer};
    splice $self->timings->{list}, ( $pointer * ( 1 + ( 2 * $self->timings_max ) ) + 1 ), 2 * $self->timings_max,
      @current_timings;

    glUseProgramObjectARB $self->shaders->{timings};
    glBindVertexArray $self->vaos->{timings};

    my $uniforms = $self->uniforms->{timings};
    glUniform1fARB $uniforms->{pointer}, $self->timings->{pointer};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{timings};

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    my $sprite_data = OpenGL::Array->new_list( GL_FLOAT, @{ $self->timings->{list} } );
    glBufferDataARB_p GL_ARRAY_BUFFER, $sprite_data, GL_STREAM_DRAW;

    glDrawArrays GL_POINTS, 0, $self->timings_max_frames;

    glDisable GL_BLEND;

    glBindVertexArray 0;

    push $self->timestamps, [ timings_render_end => time ];

    return;
}

sub render_random_sprite {
    my ( $self, %args ) = @_;
    $args{color} ||= [ rand(), rand(), rand(), rand() ];
    $args{location} ||= [ 2 * ( rand() - .5 ), 2 * ( rand() - .5 ), 0 ];
    $args{rotation} //= 360 * rand();
    $args{scale}    //= rand();
    $args{texture}  //= "player1";
    $self->render_sprite( $args{location}, $args{color}, $args{rotation}, $args{scale}, $args{texture} );
    return;
}

sub render_sprite {
    my ( $self, @args ) = @_;
    $self->with_sprite_setup(
        sub {
            $self->send_sprite_data( @args );
        }
    );
    return;
}

sub with_sprite_setup {
    my ( $self, $code, @args ) = @_;

    $self->sprites( {} );
    $self->sprite_count( 0 );
    $code->( @args );
    $self->with_sprite_setup_render;

    return;
}

sub with_sprite_setup_render {
    my ( $self ) = @_;

    glUseProgramObjectARB $self->shaders->{sprites};
    glBindVertexArray $self->vaos->{sprite};

    my $uniforms = $self->uniforms->{sprites};
    glUniform2fARB $uniforms->{camera}, @{ $self->client_game_state->{camera}{pos} }{qw( x y )};

    glActiveTextureARB GL_TEXTURE0;

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{sprite};

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    my $sprites = $self->sprites;
    for my $tex ( @{ $self->sprite_tex_order } ) {
        glBindTexture GL_TEXTURE_2D, $self->textures->{$tex};
        glUniform1iARB $uniforms->{texture}, 0;
        my $sprite_data = OpenGL::Array->new_list( GL_FLOAT, @{ $sprites->{$tex} } );
        glBufferDataARB_p GL_ARRAY_BUFFER, $sprite_data, GL_STREAM_DRAW;

        my $count = @{ $sprites->{$tex} } / 10;
        glDrawArrays GL_POINTS, 0, $count;
        $self->sprite_count( $self->sprite_count + $count );
    }

    glDisable GL_BLEND;

    glBindVertexArray 0;

    return;
}

sub send_sprite_data {
    my ( $self, @args ) = @_;
    $self->send_sprite_datas( [@args] );
    return;
}

sub send_sprite_datas {
    my ( $self, @datas ) = @_;
    my $sprites = $self->sprites;
    push @{ $sprites->{ $_->[0] } }, @{ $_->[1] } for @datas;
    return;
}

sub render_post_process {
    my ( $self ) = @_;

    glUseProgramObjectARB $self->shaders->{post_process};
    glActiveTextureARB GL_TEXTURE0;
    glEnable GL_BLEND;
    glBlendFunc GL_ONE, GL_ONE_MINUS_SRC_ALPHA;

    glBindTexture GL_TEXTURE_2D, $self->textures->{fbo_color_post_process};
    glDrawArrays GL_POINTS, 0, 1;
    glDisable GL_BLEND;

    return;
}

sub render_screen_target {
    my ( $self ) = @_;

    glUseProgramObjectARB $self->shaders->{screen_target};
    glActiveTextureARB GL_TEXTURE0;
    glEnable GL_BLEND;
    glBlendFunc GL_ONE, GL_ONE_MINUS_SRC_ALPHA;

    glBindTexture GL_TEXTURE_2D, $self->textures->{fbo_color_screen_target};
    glDrawArrays GL_POINTS, 0, 1;
    glDisable GL_BLEND;

    return;
}

sub print_text_2D {
    my ( $self, @texts ) = @_;

    my $uniforms = $self->uniforms->{text};

    glUseProgramObjectARB $self->shaders->{text};
    glBindVertexArray $self->vaos->{text_vertices};

    glActiveTextureARB GL_TEXTURE0;
    glBindTexture GL_TEXTURE_2D, $self->textures->{text};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{text_vertices};

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    for my $text ( @texts ) {
        my ( $x, $y, $size, $color ) = @{ $text->[0] };

        $x          //= 0;
        $y          //= 0;
        $size       //= 16;
        $color      //= [ 1, 1, 1 ];
        $color->[3] //= 1.0;

        my $size_x = $size / 2;
        my @chars = split //, $text->[1];

        my @vertices = map { $x + $_ * $size_x, $y, ord $chars[$_] } 0 .. $#chars;

        glUniform2fARB $uniforms->{size}, 2 * $size_x, 2 * $size;
        glUniform4fARB $uniforms->{color}, @{$color};

        my $vert_ogl = OpenGL::Array->new_list( GL_FLOAT, @vertices );
        glBufferDataARB_p GL_ARRAY_BUFFER, $vert_ogl, GL_STREAM_DRAW;

        glDrawArrays GL_POINTS, 0, scalar @chars;
    }

    glDisable GL_BLEND;

    glBindVertexArray 0;

    return;
}

sub load_texture {
    my ( $self, $path ) = @_;

    my $img = OpenGL::Image->new( engine => 'Targa', source => $path );
    my ( $ifmt, $fmt, $type ) = $img->Get( 'gl_internalformat', 'gl_format', 'gl_type' );
    my ( $w, $h ) = $img->Get( 'width', 'height' );

    my $tex = glGenTextures_p 1;
    glActiveTextureARB GL_TEXTURE0;
    glBindTexture GL_TEXTURE_2D, $tex;
    glTexImage2D_c GL_TEXTURE_2D, 0, $ifmt, $w, $h, 0, $fmt, $type, $img->Ptr;
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST;
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST;

    return wantarray ? ( $tex, $w, $h ) : $tex;
}

sub load_shader_set {
    my ( $self, $vert, $frag, $geom ) = @_;
    my $t = time;
    my $geom_id;

    if ( $geom ) {
        $geom_id = $self->LoadShader( GL_GEOMETRY_SHADER, $geom );
        say "load geom:       ", time - $t, " s";
        $t = time;
    }
    my $vert_id = $self->LoadShader( GL_VERTEX_SHADER, $vert );
    say "load vert:       ", time - $t, " s";
    $t = time;
    my $frag_id = $self->LoadShader( GL_FRAGMENT_SHADER, $frag );
    say "load frag:       ", time - $t, " s";
    $t = time;
    my $program_id = $self->CreateProgram( defined( $geom_id ) ? $geom_id : (), $vert_id, $frag_id );
    say "compile program: ", time - $t, " s";
    return $program_id;
}

sub LoadShader {
    my ( $self, $eShaderType, $strShaderFilename ) = @_;

    my $strShaderFile = io->file( $strShaderFilename )->all;

    my $shader = glCreateShaderObjectARB $eShaderType;

    glShaderSourceARB_p $shader, $strShaderFile;
    glCompileShaderARB $shader;

    my $status = glGetShaderiv_p $shader, GL_COMPILE_STATUS;
    if ( $status == GL_FALSE ) {
        my $stat = glGetShaderInfoLog_p $shader;
        confess "Shader compile log: $stat" if $stat;
    }

    return $shader;
}

sub CreateProgram {
    my ( $self, @shaderList ) = @_;

    my $program = glCreateProgramObjectARB();

    glAttachShader $program, $_ for @shaderList;

    glLinkProgramARB $program;

    my $status = glGetProgramiv_p $program, GL_LINK_STATUS;
    if ( $status == GL_FALSE ) {
        my $stat = glGetInfoLogARB_p $program;
        confess "Shader link log: $stat" if $stat;
    }

    glDetachObjectARB $program, $_ for @shaderList;

    glDeleteShader $_ for @shaderList;

    return $program;
}

sub new_vbo { shift->vbos->{ shift() } = glGenBuffersARB_p 1 }
sub new_vao { shift->vaos->{ shift() } = glGenVertexArrays_p 1 }

sub load_vertex_buffer {
    my ( $self, $name, @data ) = @_;

    my $vbo = $self->new_vbo( $name );
    glBindBufferARB GL_ARRAY_BUFFER, $vbo;
    my $v = OpenGL::Array->new_list( GL_FLOAT, @data );
    glBufferDataARB_p GL_ARRAY_BUFFER, $v, GL_STREAM_DRAW;
    glBindBufferARB GL_ARRAY_BUFFER, 0;

    return;
}
