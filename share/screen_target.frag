#version 330

in vec2 f_uv;

uniform sampler2D texture;
uniform float aspect_ratio;
uniform float display_scale;

out vec4 FragColor;

void main() {
    vec4 sum = vec4(0);

    float y = display_scale / 200;
    float x = y * aspect_ratio;
    float inverse_ar = 1 / aspect_ratio;

    for( float xi = -x ; xi < x ; xi += 1.0 ) {
        for ( float yi = -y ; yi < y ; yi += 1.0 ) {
            float distance = sqrt( pow( yi, 2.0 ) + pow( xi * inverse_ar, 2.0 ) );
            if( distance <= y ) {
                sum += texture2D( texture, f_uv + vec2( yi, xi ) * 0.004 ) * 0.25;
            }
        }
    }

    vec4 sample = texture2D( texture, f_uv );
    float val = (sample.r + sample.g + sample.b + sample.a) / 4;
    float mult = 0.14 / pow( ( val + 1.0 ), 6.0 ); // https://www.desmos.com/calculator/tor44pgxi4
    FragColor = sum * sum * mult + sample;
}
