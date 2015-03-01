#version 330

layout (location = 0) in vec4 color;
layout (location = 1) in vec3 offset;
layout (location = 2) in float rotation;
layout (location = 3) in float scale;

uniform vec2 camera;
uniform float display_scale;
uniform float aspect_ratio;

out VS_OUT {
    vec4 color;
    mat4 matrix;
} vs_out;

void main() {
    vec2 pos =  vec2( ( offset.x - camera.x ) / display_scale,
                      ( offset.y - camera.y ) / display_scale );

    mat4 translate_mat = mat4(
        1.0,     0.0,     0.0,        0.0,
        0.0,     1.0,     0.0,        0.0,
        0.0,     0.0,     1.0,        0.0,
        pos.x,   pos.y,   offset.z,   1.0
    );

    float r_rotation = radians( rotation );
    mat4 rotate_mat = mat4(
        cos(r_rotation),  -sin(r_rotation),  0.0,  0.0,
        sin(r_rotation),  cos(r_rotation),   0.0,  0.0,
        0.0,              0.0,               1.0,  0.0,
        0.0,              0.0,               0.0,  1.0
    );

    mat4 scale_mat = mat4(
        0.5 * scale,    0.0,            0.0,            0.0,
        0.0,            0.5 * scale,    0.0,            0.0,
        0.0,            0.0,            0.5 * scale,    0.0,
        0.0,            0.0,            1.0,            1.0
    );

    float near = 0.001;
    float far = 10000.0;
    float range = near - far;
    float tanHalfFOV = tan( radians ( 90.0 / 2.0 ) );

    mat4 perspmat = mat4(
        1.0 / ( tanHalfFOV * aspect_ratio ), 0.0,              0.0,                          0.0,
        0.0,                                 1.0 / tanHalfFOV, 0.0,                          0.0,
        0.0,                                 0.0,              ( 0.0 - near - far ) / range, 1.0,
        0.0,                                 0.0,              2.0 * far * near / range,     0.0
    );

    vs_out.color = color;
    vs_out.matrix = perspmat * translate_mat * rotate_mat * scale_mat;
}
