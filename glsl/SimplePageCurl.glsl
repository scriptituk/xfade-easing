// Name: SimplePageCurl
// Author: Andrew Hung
// License: MIT
// Adapted by Raymond Luckhurst from:
// https://www.shadertoy.com/view/ls3cDB
// see https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/

const float M_PI = 3.14159265358;

uniform int angle; // = 80
uniform float radius; // = 0.1
uniform bool roll; // = false
uniform bool uncurl; // = false
uniform float opacity; // = 0.8
uniform float shadow; // = 0.2

vec4 transition (vec2 uv) {
    // setup
    float phi = M_PI * float(angle) / 180. - M_PI / 2.; // target curl angle
    vec2 dir = normalize(vec2(cos(phi) * ratio, sin(phi))); // direction unit vector
    vec2 i = dir * dot(sign(dir) * .5, dir); // initial position, curl axis on quadrant corner
    vec2 f = -(i + dir * radius); // final position, curl just out of view
    vec2 m = f - i; // travel extent, perpendicular to curl axis

    // get point relative to curl axis
    vec2 p = i + m * (uncurl ? 1. - progress : progress); // current position, origin
    vec2 q = uv - .5; // distance of current point from centre
    float dist = dot(q - p, dir); // distance of point from curl axis
    p = q - dir * dist; // point perpendicular to curl axis

    // map point to curl
    vec4 a = getFromColor(uv), b = getToColor(uv), c = uncurl ? a : b;
    bool o = false, s = false; // opacity & shadow flags
    if (dist < 0.) { // point is over flat A
        c = uncurl ? b : a;
        if (!roll) {
            p += dir * (M_PI * radius - dist) + .5;
            if (p.x >= 0. && p.x <= 1. && p.y >= 0. && p.y <= 1.) // on flat back of A
                c = uncurl ? getToColor(p) : getFromColor(p), o = true;
        }
    } else if (radius > 0.) { // point is over curling A or flat B
        // map to cylinder point
        float theta = asin(dist / radius);
        vec2 p2 = p + dir * (M_PI - theta) * radius + .5;
        vec2 p1 = p + dir * theta * radius + .5;
        if (p2.x >= 0. && p2.x <= 1. && p2.y >= 0. && p2.y <= 1.) // on curling back of A
            c = uncurl ? getToColor(p2) : getFromColor(p2), o = s = true;
        else if (p1.x >= 0. && p1.x <= 1. && p1.y >= 0. && p1.y <= 1.) // on curling front of A
            c = uncurl ? getToColor(p1) : getFromColor(p1);
        else // on B
            s = true;
    }
    if (o)
        c.rgb += (1. - c.rgb) * opacity;
    if (s) // TODO: ok over A, makes a tideline over B for large radius
        c.rgb *= pow(clamp(abs(dist - radius) / radius, 0., 1.), shadow);
    return c;
}