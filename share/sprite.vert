#version 330

layout (location = 0) in vec3 vertex_pos;
layout (location = 1) in vec2 tex_coord;

uniform vec2 offset;
uniform float rotation;
uniform float scale;

out vec2 TexCoord0;
out vec4 frag_color;

void main() {
    mat3 translate_mat = mat3(
        1.0,        0.0,        0.0,
        0.0,        1.0,        0.0,
        offset.x, offset.y, 1.0
    );

    mat3 rotate_mat = mat3(
        cos(rotation),  -sin(rotation),  0.0,
        sin(rotation),  cos(rotation),  0.0,
        0.0,            0.0,            1.0
    );

    mat3 scale_mat = mat3(
        0.5 * scale,    0.0,            0.0,
        0.0,            0.5 * scale,    0.0,
        0.0,            0.0,            1.0
    );

    vec3 transformed = translate_mat * rotate_mat * scale_mat * vec3(vertex_pos.x,vertex_pos.y,1.0);

    gl_Position = vec4( transformed, 1.0 ); //  * rotate_mat * scale_mat

    TexCoord0 = tex_coord;
}
