#version 330 core

in vec2 UV; // Interpolated values from the vertex shaders

out vec4 out_color; // Ouput data

uniform vec4 color;
uniform sampler2D texture; // Values that stay constant for the whole mesh.

void main(){
	out_color = texture2D( texture, UV );
	out_color = vec4( color.x, color.y, color.z, color.w * out_color.w );
}
