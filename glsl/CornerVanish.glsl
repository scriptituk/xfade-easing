// Name: CornerVanish
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 6)

vec4 transition (vec2 uv) {
    float b1 = (1. - progress) / 2., b2 = 1. - b1;
    bool bx = uv.x > b1 && uv.x < b2;
    bool by = uv.y > b1 && uv.y < b2;
    return (bx || by) ? getToColor(uv) : getFromColor(uv);
}
