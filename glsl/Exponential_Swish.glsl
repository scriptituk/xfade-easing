// Name: Exponential_Swish
// Author: Boundless
// License: MIT
// Adapted by Raymond Luckhurst
// https://www.vegascreativesoftware.info/us/forum/gl-transitions-gallery-sharing-place-share-the-code-here--133472/?page=2#ca855233

#define PI 3.14159265
uniform float zoom;// =0.8
uniform float angle;// =0.0
uniform vec2 offset;// =vec2(0.0,0.0)
uniform int exponent;// =4
uniform ivec2 wrap;// =ivec2(2, 2)
uniform float blur;// =0.5
uniform float frames;// =60.0 Frame_Count
                     //
vec2 rot (float a, vec2 uv) {
  uv.x *= ratio;
  uv.x -= (ratio-1.)/2.;
  uv -= 0.5;
  uv = uv * mat2(cos(a),-sin(a),sin(a),cos(a));
  uv += 0.5;
  uv.x += (ratio-1.)/2.;
  uv.x /= ratio;
  return uv;
}

vec4 transition (vec2 uv) {
    float deg = angle / 180. * PI;
    uv -= 0.5;
    vec4 comp = vec4(0.);
    for (int i = 0; i < 50; i++) {
        float p = clamp(progress + float(i) * blur / frames / 50., 0.0, 1.0);
        float px0, px1, px2, px3, pa0, pa1;
        pa0 = pow(2. * p, float(exponent));
        pa1 = pow(-2. * p + 2., float(exponent));
        px0 = (-pa0 * abs(zoom)) + 1.;
        px1 = (-pa1 * abs(zoom)) + 1.;
        px2 = (-pa0 * max(-zoom, 0.)) + 1.;
        px3 = (-pa1 * max(zoom, 0.)) + 1.;
        vec2 uv0, uv1;
        if (zoom > 0.) {
            uv0 = uv * px0;
            uv1 = uv / px1;
        } else if (zoom < 0.) {
            uv0 = uv / px0;
            uv1 = uv * px1;
        } else {
            uv0 = uv;
            uv1 = uv;
        }
        uv0 += 0.5;
        uv0 -= (pa0 / px2) * offset;
        uv0 = rot(deg * pa0, uv0);
        uv1 += 0.5;
        uv1 += (pa1 / px3) * offset;
        uv1 = rot(-deg * pa1, uv1);
        if (wrap.x == 2) {
            uv0.x = acos(cos(PI * uv0.x)) / PI;
            uv1.x = acos(cos(PI * uv1.x)) / PI;
        } else if (wrap.x == 1) {
            uv0.x = mod(uv0.x, 1.0);
            uv1.x = mod(uv1.x, 1.0);
        }
        if (wrap.y == 2) {
            uv0.y = acos(cos(PI * uv0.y)) / PI;
            uv1.y = acos(cos(PI * uv1.y)) / PI;
        } else if (wrap.y == 1) {
            uv0.y = mod(uv0.y, 1.0);
            uv1.y = mod(uv1.y, 1.0);
        }
        vec4 c = (p < 0.5) ? getFromColor(uv0) : getToColor(uv1);
        if (wrap.x == 0) {
            if (p < 0.5)
                c = (uv0.x >= 0.0 && uv0.x <= 1.0) ? c : vec4(0.0);
            else
                c = (uv1.x >= 0.0 && uv1.x <= 1.0) ? c : vec4(0.0);
        }
        if (wrap.y == 0) {
            if (p < 0.5)
                c = (uv0.y >= 0.0 && uv0.y <= 1.0) ? c : vec4(0.0);
            else
                c = (uv1.y >= 0.0 && uv1.y <= 1.0) ? c : vec4(0.0);
        }
        if (blur == 0.0) {
            comp = c;
            break;
        }
        comp += c / 50.;
    }
    return comp;
}
