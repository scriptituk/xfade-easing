// Name: Stripe_Wipe
// Author: Boundless
// License: MIT
// Adapted by Raymond Luckhurst
// https://www.vegascreativesoftware.info/us/forum/gl-transitions-gallery-sharing-place-share-the-code-here--133472/?page=1#ca839572

#define PI 3.14159265

uniform int nlayers; //= 3
uniform float layerSpread; //= 0.5
uniform vec4 color1; //= vec4(0.2, 0.1, 0.8, 1.0)
uniform vec4 color2; //= vec4(0.4, 0.8, 1.0, 1.0)
uniform float shadowIntensity; //= 0.7
uniform float shadowSpread; //= 0.
uniform float angle; //= 0.

vec4 transition(vec2 uv) {
    float rad = angle * PI / 180.;
    vec2 p = uv;
    p = vec2(p.x * ratio, p.y);
    p.x -= (ratio - 1.) / 2.;
    float offset = abs(sin(rad)) + abs(cos(rad) * ratio);
    p -= 0.5;
    p /= offset;
    p = p * mat2(cos(rad), -sin(rad), sin(rad), cos(rad));
    p += 0.5;
    float px = pow(-p.x + 1.0, 1./3.);
    float lspread = (px + ((1. + layerSpread) * progress - 1.)) * float(nlayers) / layerSpread;
    float colorMix = (nlayers == 1) ? floor(lspread) * 2. : floor(lspread) / (float(nlayers) - 1.);
    float colorShade = fract(lspread) * shadowIntensity + shadowSpread;
    colorShade = 1. - clamp(colorShade, 0., 1.);
    if (colorMix >= 1. || colorMix < -2. / float(nlayers) || nlayers == 1)
        colorShade = 1.0;
    vec4 shadeComp = clamp(vec4(colorShade, colorShade * 1.05, colorShade * 1.3, 1.0), 0.0, 1.0);
    shadeComp = sin(shadeComp * PI / 2.);
    if (colorMix >= 0. && colorMix <= 1.)
        return vec4(mix(color1, color2, colorMix)) * shadeComp;
//  colorMix = lspread / (float(nlayers) - 1.);
    vec4 colorComp = (progress > colorMix) ? getFromColor(uv) : getToColor(uv);
    if (colorMix < 0.)
        colorComp *= mix(vec4(1.0), shadeComp, clamp(progress * 10., 0., 1.));
    return colorComp;
}

