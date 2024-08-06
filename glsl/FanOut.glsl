// Name: FanOut
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 26)

uniform float smooth; // = 0.05

const float M_PI = 3.14159265358;

vec4 transition (vec2 uv) {
    vec4 a = getFromColor(uv), b = getToColor(uv);
    float theta = 2. * M_PI * progress;
    float d = M_PI + atan(0.5 - uv.y, (uv.x < 0.5) ? 0.25 - uv.x : uv.x - 0.75) - theta;
    if (d < 0.)
        return b;
    return (d < smooth) ? mix(b, a, d / smooth) : a;
}
