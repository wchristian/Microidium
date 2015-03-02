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
    mat4 matrix = gs_in[0].matrix;
    f_color = gs_in[0].color;
    
    float sprite_half_width = sprite_size / 2;
    float sprite_half_width_in_scale = sprite_half_width / display_scale;

    f_uv = vec2( 0.0, 1.0 );
    gl_Position = matrix * vec4( -sprite_half_width_in_scale, -sprite_half_width_in_scale, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 0.0, 0.0 );
    gl_Position = matrix * vec4( -sprite_half_width_in_scale, sprite_half_width_in_scale, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 1.0, 1.0 );
    gl_Position = matrix * vec4( sprite_half_width_in_scale, -sprite_half_width_in_scale, 0.0, 1.0 );
    EmitVertex();

    f_uv = vec2( 1.0, 0.0 );
    gl_Position = matrix * vec4( sprite_half_width_in_scale, sprite_half_width_in_scale, 0.0, 1.0 );
    EmitVertex();

    EndPrimitive();
}
