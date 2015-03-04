#version 330

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

in VS_OUT {
    vec4 color;
    mat4 matrix;
} gs_in[];

uniform float display_scale;
uniform float sprite_size;

out vec4 f_color;
out vec2 f_uv;

void main() {
    f_color = gs_in[0].color;

    f_uv = vec2( 0.0, 0.0 );
    gl_Position = vec4( -1, -1, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 0.0, 1.0 );
    gl_Position = vec4( -1, 1, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 1.0, 0.0 );
    gl_Position = vec4( 1, -1, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 1.0, 1.0 );
    gl_Position = vec4( 1, 1, 0.0, 1.0 );
    EmitVertex();

    EndPrimitive();
}
