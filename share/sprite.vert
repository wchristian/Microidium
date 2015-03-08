#version 330

layout (location = 0) in vec4 color;
layout (location = 1) in vec3 offset;
layout (location = 2) in float rotation;
layout (location = 3) in float scale;
layout (location = 4) in float r_scale;

uniform vec2 camera;
uniform float display_scale;
uniform float aspect_ratio;
uniform float fov;

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

    float scale_x = scale;
    if( r_scale != 0.0 ) {
        float target = rotation < 180.0 ? 90.0 : 270.0;
        float rot_diff = abs( target - rotation );
        rot_diff /= 90.0;
        scale_x *= rot_diff;
    }

    mat4 scale_mat = mat4(
        0.5 * scale_x,  0.0,            0.0,            0.0,
        0.0,            0.5 * scale,    0.0,            0.0,
        0.0,            0.0,            0.5 * scale,    0.0,
        0.0,            0.0,            1.0,            1.0
    );

    float near = 0.001;
    float far = 10000.0;
    float range = near - far;
    float tanHalfFOV = tan( radians ( fov / 2.0 ) );

    mat4 perspmat = mat4(
        1.0 / ( tanHalfFOV * aspect_ratio ), 0.0,              0.0,                          0.0,
        0.0,                                 1.0 / tanHalfFOV, 0.0,                          0.0,
        0.0,                                 0.0,              ( 0.0 - near - far ) / range, 1.0,
        0.0,                                 0.0,              2.0 * far * near / range,     0.0
    );

    vs_out.color = color;
    if (offset.z > 0.0) {
        float max_dist = 4.0;
        float dim = min( 1.0, offset.z / max_dist );
        vs_out.color.r -= ( vs_out.color.r - 0.3 ) * dim;
        vs_out.color.g -= vs_out.color.g * dim;
        vs_out.color.b -= vs_out.color.b * dim;
    }

    vs_out.matrix = perspmat * translate_mat * rotate_mat * scale_mat;
}
