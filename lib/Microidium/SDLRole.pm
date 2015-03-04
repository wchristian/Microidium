package Microidium::SDLRole;

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
use Math::Trig qw' rad2deg ';
use Acme::MITHALDU::XSGrabBag 'deg2rad';
use Carp 'confess';

use Microidium::Helpers 'dfile';

use Moo::Role;

has app => ( is => 'lazy', handles => [qw( run stop sync )] );

has display_scale      => ( is => 'rw', default => sub { 600 } );
has width              => ( is => 'rw', default => sub { 800 } );
has height             => ( is => 'rw', default => sub { 600 } );
has aspect_ratio       => ( is => 'rw', default => sub { 800 / 600 } );
has sprite_size        => ( is => 'rw', default => sub { 160 } );
has fov                => ( is => 'rw', default => sub { 90 } );
has frame              => ( is => 'rw', default => sub { 0 } );
has fps                => ( is => 'rw', default => sub { 0 } );
has frame_time         => ( is => 'rw', default => sub { 0 } );
has last_frame_time    => ( is => 'rw', default => sub { time } );
has current_frame_time => ( is => 'rw', default => sub { time } );
has $_ => ( is => 'rw', default => sub { 0 } ) for qw( render_time world_time ui_time );

has $_ => ( is => 'rw', builder => 1 ) for qw( event_handlers game_state client_state );

has $_ => ( is => 'ro', default => sub { {} } ) for qw( textures shaders uniforms attribs vbos );
has sprites          => ( is => 'rw', default => sub { {} } );
has sprite_count     => ( is => 'rw', default => sub { 0 } );
has sprite_tex_order => ( is => 'rw', default => sub { [] } );
has [qw(fbo depth_texture color_texture)] => ( is => "rw" );

BEGIN {
    my @gl_constants = qw(
      GL_TEXTURE_2D GL_FLOAT GL_FALSE GL_TRIANGLES GL_COLOR_BUFFER_BIT
      GL_TEXTURE0 GL_ARRAY_BUFFER GL_BLEND GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
      GL_ARRAY_BUFFER GL_STATIC_DRAW GL_TEXTURE0 GL_TEXTURE_MIN_FILTER
      GL_TEXTURE_MAG_FILTER GL_NEAREST GL_VERTEX_SHADER GL_FRAGMENT_SHADER
      GL_COMPILE_STATUS GL_LINK_STATUS GL_GEOMETRY_SHADER GL_POINTS
      GL_LINEAR GL_TEXTURE_WRAP_S GL_CLAMP GL_TEXTURE_WRAP_T GL_RGBA
      GL_DEPTH_COMPONENT GL_FRAMEBUFFER GL_DRAW_FRAMEBUFFER
      GL_COLOR_ATTACHMENT0_EXT GL_DEPTH_ATTACHMENT GL_FRAMEBUFFER_COMPLETE
      GL_ONE GL_ONE_MINUS_SRC_ALPHA
    );

    for my $name ( @gl_constants ) {
        my $val = eval "Acme::MITHALDU::BleedingOpenGL::$name()";
        eval "sub $name () { $val }";
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
        min_t          => 1 / 62,
    );

    $self->init_sprites;
    $self->init_text_2D( dfile "courier.tga" );
    $self->init_fbo;
    $self->init_screen_target;

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
    my $type     = $event->type;
    my $handlers = $self->event_handlers;
    die "unknown event type: $type" if !exists $handlers->{$type};
    return unless my $meth = $handlers->{$type};
    $self->$meth( $event );
    return;
}

sub on_videoresize {
    my ( $self, $event ) = @_;

    $self->width( $event->resize_w );
    $self->height( $event->resize_h );
    $self->aspect_ratio( $self->width / $self->height );

    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{aspect_ratio}, $self->aspect_ratio;

    glUseProgramObjectARB $self->shaders->{text};
    glUniform2fARB $self->uniforms->{text}{screen}, $self->width, $self->height;

    glViewport( 0, 0, $self->width, $self->height );

    return;
}

sub change_fov {
    my ( $self, $fov ) = @_;
    $self->fov( $fov );
    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{fov}, $self->fov;
    return;
}

sub on_move {
    my ( $self ) = @_;
    my $new_game_state = clone $self->game_state;
    $self->update_game_state( $new_game_state, $self->client_state );
    $self->game_state( $new_game_state );
    return;
}

sub on_show {
    my ( $self ) = @_;
    $self->frame( $self->frame + 1 );
    $self->last_frame_time( $self->current_frame_time );
    my $now = time;
    $self->current_frame_time( $now );
    $self->smooth_update( frame_time => $now - $self->last_frame_time );
    $self->render;
    $self->smooth_update( render_time => time - $now );
    $self->sync;
    return;
}

sub render {
    my ( $self ) = @_;

    my $game_state = $self->game_state;

    my $now = time;
    glBindFramebufferEXT GL_DRAW_FRAMEBUFFER, $self->fbo;    # render target: fbo
    glClearColor 0.3, 0, 0, 1;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_world( $game_state );
    $self->smooth_update( world_time => time - $now );

    glBindFramebufferEXT GL_FRAMEBUFFER, 0;                  # render target: screen
    glClearColor 0, 0, 0, 0;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_screen_target;

    my $now2 = time;
    $self->render_ui( $game_state );
    $self->smooth_update( ui_time => time - $now2 );

    return;
}

sub smooth_update {
    my ( $self, $attrib, $new ) = @_;
    my $old  = $self->$attrib;
    my $diff = $new - $old;
    $self->$attrib( $old + $diff * .08 );
    return;
}

sub glGetAttribLocationARB_p_safe {
    my ( $self, $shader_name, $attrib_name ) = @_;
    my $shader = $self->shaders->{$shader_name};
    my $ret = glGetAttribLocationARB_p $shader, $attrib_name;

    #die "Could not find attribute '$attrib_name' in '$shader_name'" if $ret == -1;
    return $ret;
}

sub glGetUniformLocationARB_p_safe {
    my ( $self, $shader_name, $attrib_name ) = @_;
    my $shader = $self->shaders->{$shader_name};
    my $ret = glGetUniformLocationARB_p $shader, $attrib_name;

    #die "Could not find uniform '$attrib_name' in '$shader_name'" if $ret == -1;
    return $ret;
}

sub init_fbo {
    my ( $self ) = @_;

    my @dim = ( $self->width, $self->height );

    # color texture
    $self->textures->{fbo_color} = $self->color_texture( glGenTextures_p 1 );
    glBindTexture GL_TEXTURE_2D,   $self->color_texture;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP;
    glTexImage2D_c GL_TEXTURE_2D,  0, GL_RGBA, @dim, 0, GL_RGBA, GL_FLOAT, 0;

    # depth texture
    $self->textures->{fbo_depth} = $self->depth_texture( glGenTextures_p 1 );
    glBindTexture GL_TEXTURE_2D,   $self->depth_texture;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP;
    glTexParameterf GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP;
    glTexImage2D_c GL_TEXTURE_2D,  0, GL_DEPTH_COMPONENT, @dim, 0, GL_DEPTH_COMPONENT, GL_FLOAT, 0;

    # fbo
    $self->fbo( glGenFramebuffersEXT_p 1 );
    glBindFramebufferEXT GL_FRAMEBUFFER, $self->fbo;

    # attach textures to fbo
    glFramebufferTexture2DEXT GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_2D, $self->color_texture, 0;
    glFramebufferTexture2DEXT GL_DRAW_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,      GL_TEXTURE_2D, $self->depth_texture, 0;

    my $Status = glCheckFramebufferStatusEXT GL_FRAMEBUFFER;
    die "FB error, status: 0x%x\n", $Status if $Status != GL_FRAMEBUFFER_COMPLETE;

    return;
}

sub init_screen_target {
    my ( $self ) = @_;

    $self->new_vbo( $_ ) for qw( screen_target );

    $self->shaders->{screen_target} = $self->load_shader_set( map dfile "screen_target.$_", qw( vert frag geom ) );
    $self->uniforms->{screen_target}{$_} = $self->glGetUniformLocationARB_p_safe( "screen_target", $_ )
      for qw( texture camera display_scale aspect_ratio sprite_size fov );
    $self->attribs->{screen_target}{$_} = $self->glGetAttribLocationARB_p_safe( "screen_target", $_ )
      for qw( color offset rotation scale );

    glUseProgramObjectARB $self->shaders->{screen_target};
    glUniform1fARB $self->uniforms->{screen_target}{display_scale}, $self->display_scale;
    glUniform1fARB $self->uniforms->{screen_target}{aspect_ratio},  $self->aspect_ratio;
    glUniform1fARB $self->uniforms->{screen_target}{sprite_size},   $self->sprite_size;
    glUniform1fARB $self->uniforms->{screen_target}{fov},           $self->fov;

    return;
}

# TODO: see https://github.com/nikki93/opengl/blob/master/main.cpp
sub init_sprites {
    my ( $self ) = @_;

    $self->new_vbo( $_ ) for qw( sprite );

    $self->shaders->{sprites} = $self->load_shader_set( map dfile "sprite.$_", qw( vert frag geom ) );
    $self->uniforms->{sprites}{$_} = $self->glGetUniformLocationARB_p_safe( "sprites", $_ )
      for qw( texture camera display_scale aspect_ratio sprite_size fov );
    $self->attribs->{sprites}{$_} = $self->glGetAttribLocationARB_p_safe( "sprites", $_ )
      for qw( color offset rotation scale );

    glUseProgramObjectARB $self->shaders->{sprites};
    glUniform1fARB $self->uniforms->{sprites}{display_scale}, $self->display_scale;
    glUniform1fARB $self->uniforms->{sprites}{aspect_ratio},  $self->aspect_ratio;
    glUniform1fARB $self->uniforms->{sprites}{sprite_size},   $self->sprite_size;
    glUniform1fARB $self->uniforms->{sprites}{fov},           $self->fov;

    $self->sprite_tex_order( [qw( blob thrust_flame thrust_right_flame thrust_left_flame player1 bullet )] );
    $self->textures->{$_} = $self->load_texture( dfile "$_.tga" ) for @{ $self->sprite_tex_order };

    return;
}

sub init_text_2D {
    my ( $self, $path ) = @_;

    $self->new_vbo( $_ ) for qw( text_vertices );

    $self->shaders->{text} = $self->load_shader_set( map dfile "text.$_", qw( vert frag ) );
    $self->uniforms->{text}{$_} = $self->glGetUniformLocationARB_p_safe( "text", $_ ) for qw( texture color screen );
    $self->attribs->{text}{$_} = $self->glGetAttribLocationARB_p_safe( "text", $_ ) for qw( vertex );

    glUseProgramObjectARB $self->shaders->{text};
    glUniform2fARB $self->uniforms->{text}{screen}, $self->width, $self->height;

    $self->textures->{text} = $self->load_texture( $path );

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

    my $uniforms = $self->uniforms->{sprites};
    glUniform2fARB $uniforms->{camera}, @{ $self->client_state->{camera} }{qw( x y )};

    glActiveTextureARB GL_TEXTURE0;

    my $attribs = $self->attribs->{sprites};
    glEnableVertexAttribArrayARB $attribs->{color};
    glEnableVertexAttribArrayARB $attribs->{offset};
    glEnableVertexAttribArrayARB $attribs->{rotation};
    glEnableVertexAttribArrayARB $attribs->{scale};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{sprite};

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    my $value_count = 4 + 3 + 1 + 1;
    my $stride      = 4 * $value_count;    # bytes * counts
    glVertexAttribPointerARB_c $attribs->{color}, 4, GL_FLOAT, GL_FALSE, $stride, 0;
    glVertexAttribPointerARB_c $attribs->{offset},   3, GL_FLOAT, GL_FALSE, $stride, ( 4 ) * 4;
    glVertexAttribPointerARB_c $attribs->{rotation}, 1, GL_FLOAT, GL_FALSE, $stride, ( 4 + 3 ) * 4;
    glVertexAttribPointerARB_c $attribs->{scale},    1, GL_FLOAT, GL_FALSE, $stride, ( 4 + 3 + 1 ) * 4;

    for my $tex ( @{ $self->sprite_tex_order } ) {
        glBindTexture GL_TEXTURE_2D, $self->textures->{$tex};
        glUniform1iARB $uniforms->{texture}, 0;
        my @vertices = map { @{$_} } @{ $self->sprites->{$tex} };
        my $sprite_data = OpenGL::Array->new_list( GL_FLOAT, @vertices );
        glBufferDataARB_p GL_ARRAY_BUFFER, $sprite_data, GL_STATIC_DRAW;

        my $count = @vertices / $value_count;
        glDrawArrays GL_POINTS, 0, $count;
        $self->sprite_count( $self->sprite_count + $count );
    }

    glDisable GL_BLEND;

    glDisableVertexAttribArrayARB $attribs->{color};
    glDisableVertexAttribArrayARB $attribs->{offset};
    glDisableVertexAttribArrayARB $attribs->{rotation};
    glDisableVertexAttribArrayARB $attribs->{scale};

    return;
}

sub send_sprite_data {
    my ( $self, @args ) = @_;
    $self->send_sprite_datas( [@args] );
    return;
}

sub send_sprite_datas {
    my ( $self, @datas ) = @_;
    for my $sprite ( @datas ) {
        my ( $location, $color, $rotation, $scale, $texture ) = @{$sprite};
        $location->[2] //= 0;
        $color ||= [ 1, 1, 1, 1 ];
        $scale //= 1;
        push @{ $self->sprites->{$texture} }, [ @{$color}, @{$location}, $rotation, $scale ];
    }
    return;
}

sub render_screen_target {
    my ( $self ) = @_;

    glUseProgramObjectARB $self->shaders->{screen_target};

    my $uniforms = $self->uniforms->{screen_target};
    glUniform2fARB $uniforms->{camera}, 0, 0;

    glActiveTextureARB GL_TEXTURE0;

    my $attribs = $self->attribs->{screen_target};
    glEnableVertexAttribArrayARB $attribs->{color};
    glEnableVertexAttribArrayARB $attribs->{offset};
    glEnableVertexAttribArrayARB $attribs->{rotation};
    glEnableVertexAttribArrayARB $attribs->{scale};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{screen_target};

    glEnable GL_BLEND;
    glBlendFunc GL_ONE, GL_ONE_MINUS_SRC_ALPHA;

    my $value_count = 4 + 3 + 1 + 1;
    my $stride      = 4 * $value_count;    # bytes * counts
    glVertexAttribPointerARB_c $attribs->{color}, 4, GL_FLOAT, GL_FALSE, $stride, 0;
    glVertexAttribPointerARB_c $attribs->{offset},   3, GL_FLOAT, GL_FALSE, $stride, ( 4 ) * 4;
    glVertexAttribPointerARB_c $attribs->{rotation}, 1, GL_FLOAT, GL_FALSE, $stride, ( 4 + 3 ) * 4;
    glVertexAttribPointerARB_c $attribs->{scale},    1, GL_FLOAT, GL_FALSE, $stride, ( 4 + 3 + 1 ) * 4;

    glBindTexture GL_TEXTURE_2D, $self->textures->{fbo_color};
    glUniform1iARB $uniforms->{texture}, 0;
    my $sprite_data = OpenGL::Array->new_list( GL_FLOAT, ( 1, 1, 1, 1 ), ( 0, 0, 0 ), 0, 10 );
    glBufferDataARB_p GL_ARRAY_BUFFER, $sprite_data, GL_STATIC_DRAW;

    glDrawArrays GL_POINTS, 0, 1;

    glDisable GL_BLEND;

    glDisableVertexAttribArrayARB $attribs->{color};
    glDisableVertexAttribArrayARB $attribs->{offset};
    glDisableVertexAttribArrayARB $attribs->{rotation};
    glDisableVertexAttribArrayARB $attribs->{scale};

    return;
}

sub print_text_2D {
    my ( $self, $settings, $text ) = @_;
    my ( $x, $y, $size, $color ) = @{$settings};

    $x     //= 0;
    $y     //= 0;
    $size  //= 16;
    $color //= [ 1, 1, 1 ];

    my $size_x = $size / 2;
    my @chars  = split //, $text;
    my $length = @chars;

    my ( @vertices, @uvs );

    for my $i ( 0 .. $length - 1 ) {
        my @vertex_up_left = ( $x + $i * $size_x, $y + $size );
        my @vertex_up_right   = ( $x + $i * $size_x + $size_x, $y + $size );
        my @vertex_down_right = ( $x + $i * $size_x + $size_x, $y );
        my @vertex_down_left = ( $x + $i * $size_x, $y );

        my $char = ord $chars[$i];
        my $uv_x = ( $char % 16 ) / 16;
        my $uv_y = int( $char / 16 ) / 16;

        my @uv_up_left = ( $uv_x, $uv_y );
        my @uv_up_right   = ( $uv_x + 1 / 16, $uv_y );
        my @uv_down_right = ( $uv_x + 1 / 16, $uv_y + 1 / 16 );
        my @uv_down_left = ( $uv_x, $uv_y + 1 / 16 );

        push @vertices,    #
          @vertex_up_left,    @uv_up_left,      #
          @vertex_down_left,  @uv_down_left,
          @vertex_up_right,   @uv_up_right,
          @vertex_down_right, @uv_down_right,
          @vertex_up_right,   @uv_up_right,
          @vertex_down_left,  @uv_down_left;
    }

    my $uniforms = $self->uniforms->{text};

    glUseProgramObjectARB $self->shaders->{text};

    glActiveTextureARB GL_TEXTURE0;
    glBindTexture GL_TEXTURE_2D, $self->textures->{text};
    glUniform1iARB $uniforms->{texture}, 0;

    glUniform3fARB $uniforms->{color}, @{$color};

    my $attribs = $self->attribs->{text};

    glEnableVertexAttribArrayARB $attribs->{vertex};
    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{text_vertices};
    my $vert_ogl = OpenGL::Array->new_list( GL_FLOAT, @vertices );
    glBufferDataARB_p GL_ARRAY_BUFFER, $vert_ogl, GL_STATIC_DRAW;
    glVertexAttribPointerARB_c $attribs->{vertex}, 4, GL_FLOAT, GL_FALSE, 0, 0;

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    glDrawArrays GL_TRIANGLES, 0, scalar( @vertices ) / 2;

    glDisable GL_BLEND;

    glDisableVertexAttribArrayARB $attribs->{vertex};

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

sub load_vertex_buffer {
    my ( $self, $name, @data ) = @_;

    my $vbo = $self->new_vbo( $name );
    glBindBufferARB GL_ARRAY_BUFFER, $vbo;
    my $v = OpenGL::Array->new_list( GL_FLOAT, @data );
    glBufferDataARB_p GL_ARRAY_BUFFER, $v, GL_STATIC_DRAW;
    glBindBufferARB GL_ARRAY_BUFFER, 0;

    return;
}
