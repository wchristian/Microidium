#version 330

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

in VS_OUT {
    vec2 pos;
    vec2 uv;
} gs_in[];

uniform vec2 size;
uniform vec2 screen;

out vec2 uv;

vec4 pv ( vec2 xy )          { return vec4( xy,   0.0, 1.0 ); }
vec4 pf ( float x, float y ) { return vec4( x, y, 0.0, 1.0 ); }

void main() {
    vec2 porigin = ( gs_in[0].pos - vec2(screen.x/2,screen.y/2) ) / vec2(screen.x/2,screen.y/2);
    vec2 poff = ( size / screen );
    
    float char_id = gs_in[0].uv.x;
    float uoff = 1.0 / 16.0;
    vec2 uorigin = vec2( mod( char_id, 16.0 ) / 16.0, uoff + int( char_id / 16.0 ) / 16.0 );
    
    uv = uorigin;
    gl_Position = pv( porigin );
    EmitVertex();

    uv = vec2( uorigin.x, uorigin.y - uoff );
    gl_Position = pf( porigin.x, porigin.y + poff.y );
    EmitVertex();

    uv = vec2( uorigin.x + uoff, uorigin.y );
    gl_Position = pf( porigin.x + poff.x, porigin.y );
    EmitVertex();

    uv = vec2( uorigin.x + uoff, uorigin.y - uoff );
    gl_Position = pf( porigin.x + poff.x, porigin.y + poff.y );
    EmitVertex();

    EndPrimitive();
}
