#version 330

in vec2 f_uv;

uniform sampler2D texture;

out vec4 FragColor;

void main() {
    FragColor = texture2D( texture, f_uv );
}
