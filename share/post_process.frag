#version 330

in vec2 f_uv;

uniform sampler2D texture;
uniform float aspect_ratio;
uniform float display_scale;

out vec4 FragColor;

// should be converted to this sometime : http://prideout.net/archive/bloom/
// note, the gauss curve matrix probably isn't very good
// also see: https://github.com/AnalyticalGraphicsInc/cesium/blob/master/Source/Shaders/PostProcessFilters/BrightPass.glsl
// http://kalogirou.net/2006/05/20/how-to-do-good-bloom-for-hdr-rendering/
// http://www.curious-creature.com/2007/02/20/fast-image-processing-with-jogl/
// https://software.intel.com/en-us/blogs/2014/07/15/an-investigation-of-fast-real-time-gpu-based-image-blur-algorithms

void main() {
    float glow_influence_units = 2.5; // how big a step is in ingame units
    float steps = 3.0;                // amount of steps in plus and minus direction
    float glow_influence_strength = 1.0 / 1.2; // maximum influence of any sampled location

    float y_size = glow_influence_units / display_scale; // size of a step on y axis in pixels
    float x_size = y_size / aspect_ratio;                // size of a step on x axis in pixels

    vec4 sum = vec4(0);
    for ( float ystepsi = -steps ; ystepsi <= steps ; ystepsi++ ) {
        float yi = ystepsi * y_size;
        for ( float xstepsi = -steps ; xstepsi <= steps ; xstepsi++ ) {
            float xi = xstepsi * x_size;
            float distance = sqrt( pow( ystepsi, 2.0 ) + pow( xstepsi, 2.0 ) );
            if( distance > steps )
              continue;
            sum += texture2D( texture, f_uv + vec2( xi, yi ) ) * ( 1 - ( distance / steps ) );
        }
    }
    sum *= glow_influence_strength;

    vec4 sample = texture2D( texture, f_uv );
    float val = (sample.r + sample.g + sample.b + sample.a) / 4;
    float mult = 0.14 / pow( ( val + 1.0 ), 6.0 ); // https://www.desmos.com/calculator/tor44pgxi4
    FragColor = sum * sum * mult + sample;
}
