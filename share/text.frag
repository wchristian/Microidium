#version 330 core

in vec2 uv; // Interpolated values from the vertex shaders

uniform vec4 color;
uniform sampler2D texture;

out vec4 out_color; // Ouput data

void main(){
	out_color = vec4( color.x, color.y, color.z, color.w * texture2D( texture, uv ).w );
}
