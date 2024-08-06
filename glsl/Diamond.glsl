// Name: Diamond
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 8)

uniform float smooth; // = 0.05

vec4 transition (vec2 uv) {
    vec4 a = getFromColor(uv), b = getToColor(uv);
    float d = abs(uv.x - .5) + abs(uv.y - .5);
    if (d < progress)
        return b;
    return (d > progress + smooth) ? a : mix(b, a, (d - progress) / smooth);
}
