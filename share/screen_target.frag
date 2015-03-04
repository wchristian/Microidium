#version 330

in vec2 f_uv;
in vec4 f_color;

uniform sampler2D texture;

out vec4 FragColor;

void main()
{
	FragColor = f_color * texture2D(texture, f_uv);
}
