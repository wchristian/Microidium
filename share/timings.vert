#version 330

in float index;
in vec4 times1;
in vec4 times2;
in vec4 times3;
in vec4 times4;
in vec4 times5;
in vec4 times6;
in vec4 times7;
in vec4 times8;
in vec4 times9;

out VS_OUT {
    float index;
    vec4 times1;
    vec4 times2;
    vec4 times3;
    vec4 times4;
    vec4 times5;
    vec4 times6;
    vec4 times7;
    vec4 times8;
    vec4 times9;
} vs_out;

void main() {
    vs_out.index = index;
    vs_out.times1 = times1;
    vs_out.times2 = times2;
    vs_out.times3 = times3;
    vs_out.times4 = times4;
    vs_out.times5 = times5;
    vs_out.times6 = times6;
    vs_out.times7 = times7;
    vs_out.times8 = times8;
    vs_out.times9 = times9;
}
