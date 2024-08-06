// Name: DoubleDiamond
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 9)

uniform float smooth; // = 0.05

vec4 transition (vec2 uv) {
    vec4 a = getFromColor(uv), b = getToColor(uv);
    float b1 = (1. - progress) / 2., b2 = 1. - b1;
    float d = abs(uv.x - .5) + abs(uv.y - .5);
    return (d >= b1 && d <= b2)
        ? (d >= b1 + smooth&& d <= b2 - smooth)
            ? b : mix(a, b, min(d - b1, b2 - d) / smooth)
        : a;
}
