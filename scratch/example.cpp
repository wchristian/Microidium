// g++ main.cpp -lGLEW -lglut -lGL
#include <GL/glew.h>
#include <GL/glut.h>
#include <iostream>
#include <vector>
#include <cmath>
using namespace std;

// OpenGL Mathematics (GLM): http://glm.g-truc.net/
#include <glm/glm.hpp>
#include <glm/gtc/random.hpp>
using namespace glm;

// stores/manipulates a list of rectangular sprites and their vertexes
struct SpriteWrangler
{
    SpriteWrangler( unsigned int aSpriteCount )
    {
        verts.resize( aSpriteCount * 4 );
        states.resize( aSpriteCount );

        for( size_t i = 0; i < states.size(); ++i )
        {
            states[i].vel = linearRand( vec2( -30, -30 ), vec2( 30, 30 ) );
            states[i].rotvel = linearRand( -1.0f, 1.0f );

            Vertex vert;
            vert.pos = linearRand( vec2( -400, -400 ), vec2( 400, 400 ) );
            vert.dim = linearRand( vec2( 20, 20 ), vec2( 60, 60 ) );
            vert.rotation = linearRand( 0.0f, 2 * 3.14159f );
            vert.r = (unsigned char)linearRand( 64.0f, 255.0f );
            vert.g = (unsigned char)linearRand( 64.0f, 255.0f );
            vert.b = (unsigned char)linearRand( 64.0f, 255.0f );
            vert.a = 255;

            vert.meta = vec2( 5, 0 );
            verts[i*4 + 0] = vert;
            vert.meta = vec2( 15, 0 );
            verts[i*4 + 1] = vert;
            vert.meta = vec2( 25, 0 );
            verts[i*4 + 2] = vert;
            vert.meta = vec2( 35, 0 );
            verts[i*4 + 3] = vert;
        }
    }

    void wrap( const float minVal, float& val, const float maxVal )
    {
        if( val < minVal )
            val = maxVal - fmod( maxVal - val, maxVal - minVal );
        else
            val = minVal + fmod( val - minVal, maxVal - minVal );
    }

    void Update( float dt )
    {
        for( size_t i = 0; i < states.size(); ++i )
        {
            Vertex& vert = verts[i*4 + 0];
            vert.pos += states[i].vel * dt;
            vert.rotation += states[i].rotvel * dt;

            wrap( -400.0f, vert.pos.x, 400.0f );
            wrap( -400.0f, vert.pos.y, 400.0f );
            wrap( 0.0f, vert.rotation, 2 * 3.14159f );

            verts[i*4 + 1].pos = verts[i*4 + 2].pos = verts[i*4 + 3].pos = vert.pos;
            verts[i*4 + 1].rotation = verts[i*4 + 2].rotation = verts[i*4 + 3].rotation = vert.rotation;
        }
    }

    struct Vertex
    {
        vec2 pos;
        vec2 dim;
        vec2 meta;
        float rotation;
        unsigned char r, g, b, a;
    };

    struct State
    {
        vec2 vel;       // units per second
        float rotvel;   // radians per second
    };

    vector< Vertex > verts;
    vector< State > states;
};

// RAII vertex attribute wrapper
struct Attrib
{
    Attrib( GLint prog, const char* name, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid* pointer )
    {
        mLoc = glGetAttribLocation( prog, name );
        if( mLoc < 0 ) return;
        glVertexAttribPointer( mLoc, size, type, normalized, stride, pointer );
        glEnableVertexAttribArray( mLoc );
    }

    ~Attrib()
    {
        if( mLoc >=0 ) glDisableVertexAttribArray( mLoc );
    }

    GLint mLoc;
};

// GLSL shader program loader
struct Program
{
    static GLuint Load( const char* vert, const char* geom, const char* frag )
    {
        GLuint prog = glCreateProgram();
        if( vert ) AttachShader( prog, GL_VERTEX_SHADER, vert );
        if( geom ) AttachShader( prog, GL_GEOMETRY_SHADER, geom );
        if( frag ) AttachShader( prog, GL_FRAGMENT_SHADER, frag );
        glLinkProgram( prog );
        CheckStatus( prog );
        return prog;
    }

private:
    static void CheckStatus( GLuint obj )
    {
        GLint status = GL_FALSE, len = 10;
        if( glIsShader(obj) )   glGetShaderiv( obj, GL_COMPILE_STATUS, &status );
        if( glIsProgram(obj) )  glGetProgramiv( obj, GL_LINK_STATUS, &status );
        if( status == GL_TRUE ) return;
        if( glIsShader(obj) )   glGetShaderiv( obj, GL_INFO_LOG_LENGTH, &len );
        if( glIsProgram(obj) )  glGetProgramiv( obj, GL_INFO_LOG_LENGTH, &len );
        std::vector< char > log( len, 'X' );
        if( glIsShader(obj) )   glGetShaderInfoLog( obj, len, NULL, &log[0] );
        if( glIsProgram(obj) )  glGetProgramInfoLog( obj, len, NULL, &log[0] );
        std::cerr << &log[0] << std::endl;
        exit( -1 );
    }

    static void AttachShader( GLuint program, GLenum type, const char* src )
    {
        GLuint shader = glCreateShader( type );
        glShaderSource( shader, 1, &src, NULL );
        glCompileShader( shader );
        CheckStatus( shader );
        glAttachShader( program, shader );
        glDeleteShader( shader );
    }
};

#define GLSL(version, shader) "#version " #version "\n" #shader

const char* vert = GLSL
(
    120,
    uniform mat4 projection;
    uniform mat4 modelview;

    attribute vec2 position;
    attribute vec2 scale;
    attribute float rotation;
    attribute vec4 color;

    attribute vec2 meta;

    varying vec4 fragColor;
    varying vec2 fragTexCoord;

    void main( void )
    {
        fragColor = color;

        vec2 off;
        vec2 tex;
        // probably a better way to do this
        if( meta.x < 10.0 )
        {
            off = vec2( -1.0, -1.0 );
            tex = vec2( 0.0, 0.0 );
        }
        else if( meta.x < 20.0 )
        {
            off = vec2( 1.0, -1.0 );
            tex = vec2( 1.0, 0.0 );
        }
        else if( meta.x < 30.0 )
        {
            off = vec2( 1.0, 1.0 );
            tex = vec2( 1.0, 1.0 );
        }
        else if( meta.x < 40.0 )
        {
            off = vec2( -1.0, 1.0 );
            tex = vec2( 0.0, 1.0 );
        }
        fragTexCoord = tex;

        // column 1,
        // column 2,
        // column 3
        mat3 scale_mat = mat3
            (
            0.5*scale.x,    0.0,            0.0,
            0.0,            0.5*scale.y,    0.0,
            0.0,            0.0,            1.0
            );

        mat3 rotate_mat = mat3
            (
            cos(rotation),  sin(rotation),  0.0,
            -sin(rotation), cos(rotation),  0.0,
            0.0,            0.0,            1.0
            );

        mat3 translate_mat = mat3
            (
            1.0,        0.0,        position.x,
            0.0,        1.0,        position.y,
            0.0, 0.0, 1.0
            );

        vec3 xformed = translate_mat * rotate_mat * scale_mat * vec3( off, 1.0 );

        gl_Position = projection * modelview * vec4( xformed, 1.0 );
    }
);

const char* frag = GLSL
(
    120,
    uniform sampler2D texture;

    varying vec4 fragColor;
    varying vec2 fragTexCoord;

    void main( void )
    {
        gl_FragColor = fragColor * texture2D( texture, fragTexCoord );
    }
);

GLuint tex = 0;
void display()
{
    // timekeeping
    static int prvTime = glutGet(GLUT_ELAPSED_TIME);
    const int curTime = glutGet(GLUT_ELAPSED_TIME);
    const float dt = ( curTime - prvTime ) / 1000.0f;
    prvTime = curTime;

    // sprite updates
    static SpriteWrangler wrangler( 100 );
    wrangler.Update( dt );
    vector< SpriteWrangler::Vertex >& verts = wrangler.verts;

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // set up projection and camera
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    double w = glutGet( GLUT_WINDOW_WIDTH );
    double h = glutGet( GLUT_WINDOW_HEIGHT );
    double ar = w / h;
    glOrtho( -400 * ar, 400 * ar, -400, 400, -1, 1);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // prepare to render
    static GLuint prog = Program::Load( vert, NULL, frag );
    glUseProgram( prog );

    GLfloat projection[16];
    glGetFloatv( GL_PROJECTION_MATRIX, projection );
    glUniformMatrix4fv( glGetUniformLocation( prog, "projection" ), 1, GL_FALSE, projection );

    GLfloat modelview[16];
    glGetFloatv( GL_MODELVIEW_MATRIX, modelview );
    glUniformMatrix4fv( glGetUniformLocation( prog, "modelview" ), 1, GL_FALSE, modelview );

    glUniform1i( glGetUniformLocation( prog, "texture" ), 0 );
    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, tex );

    // render
    {
        
        glVertexAttribPointer( mLoc, size,        type, normalized,                         stride, pointer );
                // prog, name, GLint size, GLenum type, normalized,                 GLsizei stride, const GLvoid* pointer )
        Attrib a1( prog, "position",    2, GL_FLOAT,      GL_FALSE, sizeof(SpriteWrangler::Vertex), &verts[0].pos.x );
        Attrib a2( prog, "meta",        2, GL_FLOAT,      GL_FALSE, sizeof(SpriteWrangler::Vertex), &verts[0].meta.x );
        Attrib a3( prog, "scale",       2, GL_FLOAT,      GL_FALSE, sizeof(SpriteWrangler::Vertex), &verts[0].dim.x );
        Attrib a4( prog, "rotation",    1, GL_FLOAT,      GL_FALSE, sizeof(SpriteWrangler::Vertex), &verts[0].rotation );
        Attrib a5( prog, "color",       4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(SpriteWrangler::Vertex), &verts[0].r );
        glDrawArrays( GL_QUADS, 0, verts.size() );
    }

    glutSwapBuffers();
}

// run display() every 16ms or so
void timer( int extra )
{
    glutTimerFunc( 16, timer, 0 );
    glutPostRedisplay();
}

int main(int argc, char **argv)
{
    glutInit( &argc, argv );
    glutInitWindowSize( 600, 600 );
    glutInitDisplayMode( GLUT_RGBA | GLUT_DEPTH | GLUT_DOUBLE );
    glutCreateWindow( "GLSL Sprites" );
    glewInit();

    // create random texture
    unsigned char buffer[ 32 * 32 * 3 ];
    for( unsigned int i = 0; i < sizeof( buffer ); ++i )
    {
        buffer[i] = (unsigned char)linearRand( 0.0f, 255.0f );
    }

    // upload texture data
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );
    glTexImage2D(GL_TEXTURE_2D, 0, 3, 32, 32, 0, GL_RGB, GL_UNSIGNED_BYTE, buffer);

    glutDisplayFunc( display );
    glutTimerFunc( 0, timer, 0 );
    glutMainLoop();
    return 0;
}
