// simple vertex shader

uniform vec2 offset;

void main() {
    vec4 totalOffset = vec4(offset.x, offset.y, 0.0, 0.0);
    gl_Position = gl_Vertex + totalOffset;

    gl_FrontColor  = gl_Color;
    gl_TexCoord[0] = gl_MultiTexCoord0;
}
