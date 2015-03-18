#version 330

layout(points) in;
layout(line_strip, max_vertices = 80) out;

in VS_OUT {
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
} gs_in[];

uniform float timings_max_frames;
uniform float pixel_width;
uniform float pixel_height;
uniform float pointer;

out vec4 f_color;

// see bin/generate_colors

const vec4 colors[23] = vec4[23](
vec4( 1.0, 0.0, 0.0, 0.85 ),
vec4( 0.690196078431373, 1.0, 0.43921568627451, 0.85 ),
vec4( 0.650980392156863, 0.0, 1.0, 0.85 ),
vec4( 1.0, 0.219607843137255, 0.219607843137255, 0.85 ),
vec4( 0.0, 1.0, 0.584313725490196, 0.85 ),
vec4( 0.803921568627451, 0.43921568627451, 1.0, 0.85 ),
vec4( 1.0, 0.43921568627451, 0.43921568627451, 0.85 ),
vec4( 0.43921568627451, 1.0, 0.764705882352941, 0.85 ),
vec4( 1.0, 0.0, 0.831372549019608, 0.85 ),
vec4( 1.0, 0.517647058823529, 0.0, 0.85 ),
vec4( 0.0, 0.901960784313726, 1.0, 0.85 ),
vec4( 1.0, 0.43921568627451, 0.905882352941176, 0.85 ),
vec4( 1.0, 0.729411764705882, 0.43921568627451, 0.85 ),
vec4( 0.0, 0.384313725490196, 1.0, 0.85 ),
vec4( 1.0, 0.0, 0.317647058823529, 0.85 ),
vec4( 0.964705882352941, 1.0, 0.0, 0.85 ),
vec4( 0.219607843137255, 0.517647058823529, 1.0, 0.85 ),
vec4( 1.0, 0.219607843137255, 0.466666666666667, 0.85 ),
vec4( 0.980392156862745, 1.0, 0.43921568627451, 0.85 ),
vec4( 0.43921568627451, 0.654901960784314, 1.0, 0.85 ),
vec4( 1.0, 0.43921568627451, 0.615686274509804, 0.85 ),
vec4( 0.450980392156863, 1.0, 0.0, 0.85 ),
vec4( 0.133333333333333, 0.0, 1.0, 0.85 )
);

float height_for( float elapsed ) {
    return 40.0 * elapsed;
}

vec4 color_for( float type ) {
    if ( type > colors.length() )
      return vec4( 1.0 );
    return colors[int(type)];
}

float draw_line( float x, float top_before, vec2 timeblock ) {
    float top = top_before + height_for( timeblock.x );
    f_color = color_for( timeblock.y );
    gl_Position = vec4( x, top_before, 0.0, 1.0 );
    EmitVertex();
    gl_Position = vec4( x, top, 0.0, 1.0 );
    EmitVertex();
    return top;
}

float draw_time_block( float x, float top0, vec4 timeblock ) {
    float top1 = draw_line( x, top0, timeblock.xy );
    float top2 = draw_line( x, top1, timeblock.zw );
    return top2;
}

void main() {
    float x_start = 1.0 - ( 5.0 + timings_max_frames ) * pixel_width * 2;
    float real_index = timings_max_frames - (pointer - gs_in[0].index);
    if ( real_index > timings_max_frames ) real_index -= timings_max_frames;
    float x = x_start + pixel_width * 2 * real_index;

    float top1 = draw_time_block( x, 0, gs_in[0].times1 );
    float top2 = draw_time_block( x, top1, gs_in[0].times2 );
    float top3 = draw_time_block( x, top2, gs_in[0].times3 );
    float top4 = draw_time_block( x, top3, gs_in[0].times4 );
    float top5 = draw_time_block( x, top4, gs_in[0].times5 );
    float top6 = draw_time_block( x, top5, gs_in[0].times6 );
    float top7 = draw_time_block( x, top6, gs_in[0].times7 );
    float top8 = draw_time_block( x, top7, gs_in[0].times8 );
    float top9 = draw_time_block( x, top8, gs_in[0].times9 );

    // mark the upper 60 fps barrier
    f_color = vec4( 0.0 );
    gl_Position = vec4( x, top9, 0.0, 1.0 );
    EmitVertex();
    float sixty = height_for(1.0/60.0);
    gl_Position = vec4( x, sixty, 0.0, 1.0 );
    EmitVertex();
    f_color = vec4( 1.0 );
    gl_Position = vec4( x - pixel_width, sixty, 0.0, 1.0 );
    EmitVertex();
    gl_Position = vec4( x, sixty + pixel_height, 0.0, 1.0 );
    EmitVertex();

    EndPrimitive();
}

