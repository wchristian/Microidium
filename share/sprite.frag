#version 330

in vec2 TexCoord0;

uniform sampler2D texture;
uniform vec4      color;

out vec4 FragColor;

void main()
{
	FragColor = color * texture2D(texture, TexCoord0);
}
