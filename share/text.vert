#version 330 core

layout(location = 0) in vec4 vertex; // x y u v

out VS_OUT {
    vec2 pos;
    vec2 uv;
} vs_out;

void main(){
    vs_out.pos = vertex.xy;
	vs_out.uv = vertex.zw;
}
