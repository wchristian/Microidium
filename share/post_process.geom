#version 330

layout(points) in;
layout(triangle_strip, max_vertices = 4) out;

out vec2 f_uv;

void main() {
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
