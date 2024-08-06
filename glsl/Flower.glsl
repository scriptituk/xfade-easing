// Name: Flower
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 13)

uniform float smooth; // = 0.05
uniform float rotation; // = 360.0

const float M_PI = 3.14159265358;

vec4 transition (vec2 uv) {
    float ang = 162.0 * M_PI / 180.0;
    vec2 v = vec2(cos(ang), sin(ang) - 1.0);
    float h = dot(v, v);
    ang = 234.0 * M_PI / 180.0;
    v = vec2(cos(ang), sin(ang) - 1.0);
    h = h - dot(v, v) / 4.0;
    ang = 36.0 * M_PI / 180.0;
    v = vec2((uv.x - 0.5) * ratio, 0.5 - uv.y);
    float theta = progress * M_PI * rotation / 180.0;
    float theta1 = atan(v.x, v.y) + theta;
    float theta2 = mod(abs(theta1), ang);
    float ro = ratio / 0.731 * progress;
    float ri = ro * (1. - sqrt(h)) / cos(ang), r;
    int i2 = int(theta1 / ang);
    if (mod(float(i2), 2.) == 0.)
        r = theta2 / ang * (ro - ri) + ri;
    else
        r = (1.0 - theta2 / ang) * (ro - ri) + ri;
    float r2 = length(v);
    vec4 a = getFromColor(uv), b = getToColor(uv);
    if (r2 > r + smooth)
        return a;
    if (r2 > r)
        return mix(b, a, (r2 - r) / smooth);
    return b;
}
