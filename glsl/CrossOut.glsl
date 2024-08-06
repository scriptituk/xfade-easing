// Name: CrossOut
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 30)

uniform float smooth; // = 0.05

vec4 transition (vec2 uv) {
    vec4 a = getFromColor(uv), b = getToColor(uv);
    float c = progress / 2.;
    float dx = uv.x - .5, dy = uv.y - .5;
    float ds = dx + dy, dd = dy - dx;
    if (ds > -c && ds < c || dd > -c && dd < c)
        return b;
    float cs = c + smooth;
    if (!(ds > -cs && ds < cs || dd > -cs && dd < cs))
        return a;
    float d = (dx >= 0.0 != dy >= 0.0) ? abs(ds) : abs(dd);
    return mix(b, a, (d - c) / smooth);
}
