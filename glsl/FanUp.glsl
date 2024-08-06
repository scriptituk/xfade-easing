// Name: FanUp
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 27)

uniform float smooth; // = 0.05

const float M_PI = 3.14159265358;

vec4 transition (vec2 uv) {
    vec4 a = getFromColor(uv), b = getToColor(uv);
    float theta = M_PI / 2.0 * progress;
    float d = atan(abs(uv.x - 0.5), 1.0 - uv.y) - theta;
    if (d < 0.)
        return b;
    return (d < smooth) ? mix(b, a, d / smooth) : a;
}
