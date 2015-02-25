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

has app => ( is => 'lazy', handles => [qw( run stop w h sync )] );

has frame              => ( is => 'rw', default => sub { 0 } );
has last_frame_time    => ( is => 'rw', default => sub { time } );
has current_frame_time => ( is => 'rw', default => sub { time } );
has $_ => ( is => 'rw', default => sub { 0 } ) for qw( render_time world_time ui_time );

has $_ => ( is => 'rw', builder => 1 ) for qw( event_handlers game_state client_state );

has $_ => ( is => 'ro', default => sub { {} } ) for qw( textures shaders uniforms attribs vbos );

BEGIN {
    my @gl_constants = qw(
      GL_TEXTURE_2D GL_FLOAT GL_FALSE GL_TRIANGLES GL_COLOR_BUFFER_BIT
      GL_TEXTURE0 GL_ARRAY_BUFFER GL_BLEND GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
      GL_ARRAY_BUFFER GL_STATIC_DRAW GL_TEXTURE0 GL_TEXTURE_MIN_FILTER
      GL_TEXTURE_MAG_FILTER GL_NEAREST GL_VERTEX_SHADER GL_FRAGMENT_SHADER
      GL_COMPILE_STATUS GL_LINK_STATUS
    );
    for my $name ( @gl_constants ) {
        my $val = eval "Acme::MITHALDU::BleedingOpenGL::$name()";
        eval "sub $name () { $val }";
    }
}

1;

sub _build_app {
    my ( $self ) = @_;

    printf "Error initializing SDL_mixer: %s\n", SDL::get_error
      if SDL::Mixer::open_audio 44100, AUDIO_S16, 2, 1024;
    SDL::Mixer::Channels::allocate_channels 32;

    my $app = SDLx::App->new(
        event_handlers => [ $self->curry::on_event ],
        move_handlers  => [ $self->curry::on_move ],
        show_handlers  => [ $self->curry::on_show ],
        gl             => 1,
    );

    $self->init_sprites;
    $self->init_text_2D( dfile "courier.tga" );

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
    $self->render;
    $self->render_time( time - $now );
    $self->sync;
    return;
}

sub render {
    my ( $self ) = @_;

    my $game_state = $self->game_state;

    my $now = time;
    glClearColor 0.3, 0, 0, 1;
    glClear GL_COLOR_BUFFER_BIT;
    $self->render_world( $game_state );    # TODO: render to texture
    $self->world_time( time - $now );
    my $now2 = time;
    $self->render_ui( $game_state );
    $self->ui_time( time - $now2 );

    return;
}

sub elapsed {
    my ( $self ) = @_;
    return $self->current_frame_time - $self->last_frame_time;
}

sub fps {
    my $elapsed = shift->elapsed;
    return $elapsed ? 1 / $elapsed : 999;
}

# TODO: see https://github.com/nikki93/opengl/blob/master/main.cpp
sub init_sprites {
    my ( $self ) = @_;

    $self->load_vertex_buffer( "sprite", $self->sprite_vbo_data );

    my $shader = $self->shaders->{sprites} = $self->load_shader_set( map dfile "sprite.$_", qw( vert frag ) );
    $self->uniforms->{sprites}{$_} = glGetUniformLocationARB_p $shader, $_
      for qw( time offset rotation scale color texture );
    $self->attribs->{sprites}{$_} = glGetAttribLocationARB_p $shader, $_ for qw( vertex_pos tex_coord );

    $self->textures->{$_} = $self->load_texture( dfile "$_.tga" )
      for qw( player1 bullet blob thrust_flame thrust_right_flame thrust_left_flame );

    return;
}

sub init_text_2D {
    my ( $self, $path ) = @_;

    $self->new_vbo( $_ ) for qw( text_vertices text_uvs );

    my $shader = $self->shaders->{text} = $self->load_shader_set( map dfile "text.$_", qw( vert frag ) );
    $self->uniforms->{text}{$_} = glGetUniformLocationARB_p $shader, $_ for qw( texture color );
    $self->attribs->{text}{$_}  = glGetAttribLocationARB_p $shader,  $_ for qw( vertexPosition_screenspace vertexUV );

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
    $self->render_sprite( %args );
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

    glUseProgramObjectARB $self->shaders->{sprites};

    glActiveTextureARB GL_TEXTURE0;

    my $attribs = $self->attribs->{sprites};
    glEnableVertexAttribArrayARB $attribs->{vertex_pos};
    glEnableVertexAttribArrayARB $attribs->{tex_coord};

    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{sprite};

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    glVertexAttribPointerARB_c $attribs->{vertex_pos}, 3, GL_FLOAT, GL_FALSE, 0, 0;
    glVertexAttribPointerARB_c $attribs->{tex_coord},  2, GL_FLOAT, GL_FALSE, 0, 18 * 4;

    $code->( @args );

    glDisable GL_BLEND;

    glDisableVertexAttribArrayARB $attribs->{vertex_pos};
    glDisableVertexAttribArrayARB $attribs->{tex_coord};

    return;
}

sub send_sprite_data {
    my ( $self, %args ) = @_;
    $args{color} ||= [ 1, 1, 1, 1 ];
    $args{scale} //= 1;
    $args{location}[2] //= 0;

    my $uniforms = $self->uniforms->{sprites};
    glBindTexture GL_TEXTURE_2D, $self->textures->{ $args{texture} };
    glUniform1iARB $uniforms->{texture}, 0;

    glUniform4fARB $uniforms->{color},    @{ $args{color} };
    glUniform3fARB $uniforms->{offset},   map 1 * $_, @{ $args{location} };
    glUniform1fARB $uniforms->{rotation}, deg2rad $args{rotation};
    glUniform1fARB $uniforms->{scale},    $args{scale};

    glDrawArrays GL_TRIANGLES, 0, 6;

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
        push @vertices,
          @vertex_up_left,    @vertex_down_left, @vertex_up_right,
          @vertex_down_right, @vertex_up_right,  @vertex_down_left;

        my $char = ord $chars[$i];
        my $uv_x = ( $char % 16 ) / 16;
        my $uv_y = int( $char / 16 ) / 16;

        my @uv_up_left = ( $uv_x, $uv_y );
        my @uv_up_right   = ( $uv_x + 1 / 16, $uv_y );
        my @uv_down_right = ( $uv_x + 1 / 16, $uv_y + 1 / 16 );
        my @uv_down_left = ( $uv_x, $uv_y + 1 / 16 );
        push @uvs,    #
          @uv_up_left,    @uv_down_left, @uv_up_right,    #
          @uv_down_right, @uv_up_right,  @uv_down_left;
    }

    my $vert_ogl = OpenGL::Array->new_list( GL_FLOAT, @vertices );
    my $uv_ogl   = OpenGL::Array->new_list( GL_FLOAT, @uvs );

    my $uniforms = $self->uniforms->{text};

    glUseProgramObjectARB $self->shaders->{text};

    glActiveTextureARB GL_TEXTURE0;
    glBindTexture GL_TEXTURE_2D, $self->textures->{text};
    glUniform1iARB $uniforms->{texture}, 0;

    glUniform3fARB $uniforms->{color}, @{$color};

    my $attribs = $self->attribs->{text};

    glEnableVertexAttribArrayARB $attribs->{vertexPosition_screenspace};
    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{text_vertices};
    glBufferDataARB_p GL_ARRAY_BUFFER, $vert_ogl, GL_STATIC_DRAW;
    glVertexAttribPointerARB_c $attribs->{vertexPosition_screenspace}, 2, GL_FLOAT, GL_FALSE, 0, 0;

    glEnableVertexAttribArrayARB $attribs->{vertexUV};
    glBindBufferARB GL_ARRAY_BUFFER, $self->vbos->{text_uvs};
    glBufferDataARB_p GL_ARRAY_BUFFER, $uv_ogl, GL_STATIC_DRAW;
    glVertexAttribPointerARB_c $attribs->{vertexUV}, 2, GL_FLOAT, GL_FALSE, 0, 0;

    glEnable GL_BLEND;
    glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA;

    glDrawArrays GL_TRIANGLES, 0, scalar @vertices;

    glDisable GL_BLEND;

    glDisableVertexAttribArrayARB $attribs->{vertexPosition_screenspace};
    glDisableVertexAttribArrayARB $attribs->{vertexUV};

    return;
}

sub sprite_vbo_data {
    return (
        # vertex coords
        -0.1, 0.1,  0,
        0.1,  -0.1, 0,
        -0.1, -0.1, 0,
        -0.1, 0.1,  0,
        0.1,  0.1,  0,
        0.1,  -0.1, 0,

        # texture coords
        0, 0,
        1, 1,
        0, 1,
        0, 0,
        1, 0,
        1, 1,
    );
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
    my ( $self, $vert, $frag ) = @_;
    my $t = time;
    my $vert_id = $self->LoadShader( GL_VERTEX_SHADER, $vert );
    say "load vert:       ", time - $t, " s";
    $t = time;
    my $frag_id = $self->LoadShader( GL_FRAGMENT_SHADER, $frag );
    say "load frag:       ", time - $t, " s";
    $t = time;
    my $program_id = $self->CreateProgram( $vert_id, $frag_id );
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
