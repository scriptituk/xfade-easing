// Name: Bounce
// Author: Adrian Purser
// License: MIT
// Altered by Raymond Luckhurst with direction parameter

uniform vec4 shadow_colour; // = vec4(0.,0.,0.,.6)
uniform float shadow_height; // = 0.075
uniform float bounces; // = 3.0
uniform int direction; // = 0

const float PI = 3.14159265358;

vec4 transition (vec2 uv) {
    float time = progress;
    float stime = sin(time * PI / 2.);
    float phase = time * PI * bounces;
    float p = (abs(cos(phase))) * (1.0 - stime);
    if (direction >= 2)
        p = 1. - p;
    float d;
    vec2 v = uv;
    if (direction == 1 || direction == 3) {
        d = v.x - p;
        v.x = d + 1.;
    } else {
        d = v.y - p;
        v.y = d + 1.;
    }
    return mix(
        mix(
            getToColor(uv),
            shadow_colour,
            step(d, shadow_height) * (1. - mix(
                ((d / shadow_height) * shadow_colour.a) + (1.0 - shadow_colour.a),
                1.0,
                smoothstep(0.95, 1., progress) // fade-out the shadow at the end
            ))
        ),
        getFromColor(v),
        step(d, 0.0)
    );
}
