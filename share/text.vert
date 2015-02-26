#version 330 core

// Input vertex data, different for all executions of this shader.
layout(location = 0) in vec4 vertex; // x y u v

out vec2 UV; // Output data ; will be interpolated for each fragment.

void main(){
	// Output position of the vertex, in clip space
	// map [0..800][0..600] to [-1..1][-1..1]
	vec2 vertexPosition_homoneneousspace = vertex.xy - vec2(400,300); // [0..800][0..600] -> [-400..400][-300..300]
	vertexPosition_homoneneousspace /= vec2(400,300);
	gl_Position =  vec4(vertexPosition_homoneneousspace,0,1);

	UV = vertex.zw; // UV of the vertex. No special space for this one.
}
