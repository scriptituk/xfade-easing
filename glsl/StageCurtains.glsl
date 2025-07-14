// Name: StageCurtains
// Author: scriptituk
// License: MIT
// inspired by Cheap Curtains by Panoptics at https://www.shadertoy.com/view/MsKGW3

uniform vec3 color; // = vec3(0.7, 0.2, 0.2)
uniform int bumps; // = 15
uniform float drop; // = 0.1

const float M_TAU = 6.28318530718;
const vec4 black = vec4(0.0, 0.0, 0.0, 1.0);

vec4 transition(vec2 uv) {
    float x = 1.0 - abs(uv.x - 0.5), y = uv.y;
    float st = (1.0 - cos(progress * M_TAU)) * 0.5;
    float tt = 1.61 - st * 0.86; // close gap/overlap
    x *= tt;
    tt *= (progress < 0.5) // slope of draw
        ? -10.0 - 1000.0 * exp2(20.0 * progress - 11.0)
        : 10.0 + 1000.0 * exp2(9.0 - 20.0 * progress);
    float xos = x + y / tt;
    vec4 c = (progress < 0.5) ? getFromColor(uv) : getToColor(uv);
    float p = 1.0 - abs(progress - 0.5) * 2.0;

    if (xos <= 0.75) {
        float miny = (cos(xos * M_TAU * float(bumps)) / 2.0 + 1.0) * 0.5;
        float d = (miny / (y * 0.125) - 30.0) / 60.0;
        y -= miny / 20.0;
        if (y > drop) // curtain
            return vec4(color + d, 1.0);
        if (y > 0.0 && drop > 0.0) {
            d = y / drop;
            c = mix(c, black, d * d * p / 2.0); // shadow
        }
    }
    return mix(c, black, p * p);
}

