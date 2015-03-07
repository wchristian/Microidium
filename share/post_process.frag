#version 330

in vec2 f_uv;

uniform sampler2D texture;
uniform float aspect_ratio;
uniform float display_scale;

out vec4 FragColor;

void main() {
    float glow_influence_units = 2.0; // how big a step is in ingame units
    float steps = 5.0;                // amount of steps in plus and minus direction

    float y_size = glow_influence_units / display_scale; // size of a step on y axis in pixels
    float x_size = y_size / aspect_ratio;                // size of a step on x axis in pixels

    vec4 sum = vec4(0);
    for ( float ystepsi = -steps ; ystepsi <= steps ; ystepsi++ ) {
        float yi = ystepsi * y_size;
        for ( float xstepsi = -steps ; xstepsi <= steps ; xstepsi++ ) {
            float xi = xstepsi * x_size;
            float distance = sqrt( pow( ystepsi, 2.0 ) + pow( xstepsi, 2.0 ) );
            if( distance <= steps ) {
                sum += texture2D( texture, f_uv + vec2( xi, yi ) ) * 0.1;
            }
        }
    }

    vec4 sample = texture2D( texture, f_uv );
    float val = (sample.r + sample.g + sample.b + sample.a) / 4;
    float mult = 0.14 / pow( ( val + 1.0 ), 6.0 ); // https://www.desmos.com/calculator/tor44pgxi4
    FragColor = sum * sum * mult + sample;
}
