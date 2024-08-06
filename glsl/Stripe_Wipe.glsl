// Name: Stripe_Wipe
// Author: Boundless
// License: MIT
// https://www.vegascreativesoftware.info/us/forum/gl-transitions-gallery-sharing-place-share-the-code-here--133472/?page=1#ca839572

#define PI 3.14159265
uniform int nlayers; //= 3
uniform float layerSpread; //= 0.5
uniform vec4 color1; //= vec4(0.2,0.1,0.8,1.0)
uniform vec4 color2; //= vec4(0.4,0.8,1.0,1.0)
uniform float shadowIntensity; //= 0.7
uniform float shadowSpread; //= 0.
uniform float angle; //= 0.
float rad = angle * PI / 180.;
vec2 rot (vec2 uv) {
  vec2 uv0 = uv;
  uv = vec2(uv.x*ratio,uv.y);
  uv.x -= (ratio-1.)/2.;
  float offset = abs(sin(rad))+abs(cos(rad)*ratio);
  uv -= 0.5;
  uv /= offset;
  uv = uv * mat2(cos(rad),-sin(rad),sin(rad),cos(rad));
  uv += 0.5;
  return uv;
}
vec4 wipe (vec2 uv) {
  float px = pow(-rot(uv).x+1.0,1./3.);
  float colorMix = ((px+((1.+layerSpread)*progress-1.))*float(nlayers)/layerSpread)/(float(nlayers)-1.);
  return mix(
    getFromColor(uv),
    getToColor(uv),
    progress > colorMix ? 0.0 : 1.0);
}
vec4 layers (vec4 colorIn, vec4 colorOut, vec2 uv) {
  float px = pow(-rot(uv).x+1.0,1./3.);
  float colorMix;
  vec4 colorComp;
  if (nlayers == 1) {
    colorMix = floor((px+((1.+layerSpread)*progress-1.))/layerSpread)*2.;
  } else {
    colorMix = floor((px+((1.+layerSpread)*progress-1.))*float(nlayers)/layerSpread)/(float(nlayers)-1.);
  }
  float colorShade = fract((px+((1.+layerSpread)*progress-1.))*float(nlayers)/layerSpread);
  colorShade = colorShade*shadowIntensity+shadowSpread;
  colorShade = clamp(colorShade,0.,1.)*-1.+1.;
  colorShade = colorMix > 1. || colorMix < -2./float(nlayers) ? 1.0 : (colorMix == 1.0 || nlayers == 1 ? 1.0 : colorShade);
  vec4 shadeComp = clamp(vec4(colorShade,colorShade*1.05,colorShade*1.3,1.0),0.0,1.0);
  shadeComp = sin(shadeComp*PI/2.);
  if(colorMix > 1.) {
    colorComp = wipe(uv);
  } else if (colorMix < 0.) {
    colorComp = wipe(uv);
    colorComp *= mix(vec4(1.0),shadeComp,clamp(progress*10.,0.,1.));
  } else {
    colorComp = vec4(mix(
      colorIn,
      colorOut,
      colorMix))*shadeComp;
  }
  return colorComp;
}
vec4 transition (vec2 uv) {
  return layers(color1, color2, uv);
}
