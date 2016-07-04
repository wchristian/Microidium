#version 330
#extension GL_EXT_texture_array : enable

in vec2 f_uv;
in vec4 f_color;

uniform sampler2DArray texture;

out vec4 FragColor;

void main()
{
	FragColor = f_color * texture2DArray(texture, vec3( f_uv, 0 ));
}
