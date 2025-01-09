// Name: Bars
// Author: Mark Craig
// mrmcsoftware on github and youtube (https://www.youtube.com/MrMcSoftware)
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/NdGfzG (type = 28)

uniform bool vertical; // = false

float rand(vec2 co) {
  return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 transition(vec2 uv) {
  vec2 p = vec2(vertical ? uv.x : uv.y, 0);
  return (rand(p) > progress) ? getFromColor(uv) : getToColor(uv);
}

