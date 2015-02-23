#version 330

layout (location = 0) in vec3 vertex_pos;
layout (location = 1) in vec2 tex_coord;

uniform vec2 offset;
uniform float rotation;
uniform float scale;

out vec2 TexCoord0;

void main() {
    mat4 translate_mat = mat4(
        1.0,        0.0,        0.0,   0.0,
        0.0,        1.0,        0.0,   0.0,
        0.0,        0.0,        1.0,   0.0,
        offset.x, offset.y,     0.0,   1.0
    );

    mat4 rotate_mat = mat4(
        cos(rotation),  -sin(rotation),  0.0,  0.0,
        sin(rotation),  cos(rotation),   0.0,  0.0,
        0.0,            0.0,             1.0,  0.0,
        0.0,            0.0,             0.0,  1.0
    );

    mat4 scale_mat = mat4(
        0.5 * scale,    0.0,            0.0,            0.0,
        0.0,            0.5 * scale,    0.0,            0.0,
        0.0,            0.0,            0.5 * scale,    0.0,
        0.0,            0.0,            1.0,            1.0
    );

    gl_Position = translate_mat * rotate_mat * scale_mat * vec4( vertex_pos.x, vertex_pos.y, 0, 1.0 );

    TexCoord0 = tex_coord;
}
