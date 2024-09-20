// Name: SimpleBookCurl
// Author: Raymond Luckhurst
// License: MIT
// Adapted from SimplePageCurl
// see simple page curl effect by Andrew Hung, https://www.shadertoy.com/view/ls3cDB
// and https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/

const float M_PI = 3.14159265359;
const float M_PI_2 = 1.57079632679;

uniform int angle; // = 150
uniform float radius; // = 0.1
uniform float shadow; // = 0.2

vec4 transition (vec2 uv) {
    // setup
    float phi = radians(float(angle)) - M_PI_2; // target curl angle
    vec2 dir = normalize(vec2(cos(phi) * ratio, sin(phi))); // direction unit vector
    vec2 q = vec2((dir.x >= 0.) ? 1. : -1., (dir.y >= 0.) ? 1. : -1.); // quadrant corner
    vec2 i = abs(dir);
    float k = (i.x == 0.) ? M_PI_2 : atan(i.y, i.x); // absolute curl angle
    i = dir * dot(q * .5, dir); // initial position, curl axis on corner
    float m1 = length(i); // length for rotating
    float m2 = M_PI * radius; // length of half-cylinder arc

    // get new angle & progress point
    float rad = radius; // working radius
    vec2 p; // working curl axis point
    float m = (m1 + m2) * progress; // current position along lengths
    if (m < m1) { // rotating page
        phi = k * (1. + cos(m / m1 * M_PI)) * .5; // eased new absolute curl angle
        dir = normalize(vec2(cos(phi), sin(phi)) * q * .5); // new direction
        p = (m1 - m) * dir;
        // TODO: prevent small radii crossing spine
    } else { // straightening curl
        if (m2 > 0.)
            rad *= pow(1. - (m - m1) / m2, 2.); // eased new radius
        dir = vec2(q.x, 0.); // new direction
        p = vec2(0., 0.);
    }

    // get point relative to curl axis
    i = uv - .5; // distance of current point from centre
    float dist = dot(i - p, dir); // distance of point from curl axis
    p = i - dir * dist; // point perpendicular to curl axis

    // map point to curl
    vec4 a = getFromColor(uv), b = getToColor(uv), c = b;
    bool s = false; // shadow flag
    if (dist < 0.) { // point is over flat A
        c = a;
        p = (p + dir * (M_PI * rad - dist)) * vec2(-1., 1.) + .5;
        if (p.x >= 0. && p.x <= 1. && p.y >= 0. && p.y <= 1.) // on flat back of A
            c = getToColor(p);
    } else if (rad > 0.) { // curled A
        // map to cylinder point
        phi = asin(dist / rad);
        vec2 p2 = (p + dir * (M_PI - phi) * rad) * vec2(-1., 1.) + .5;
        vec2 p1 = p + dir * phi * rad + .5;
        if (p2.x >= 0. && p2.x <= 1. && p2.y >= 0. && p2.y <= 1.) // on curling back of A
            c = getToColor(p2), s = true;
        else if (p1.x >= 0. && p1.x <= 1. && p1.y >= 0. && p1.y <= 1.) // on curling front of A
            c = getFromColor(p1);
        else // on B
            s = true;
    }
    if (s) // TODO: ok over A, makes a tideline over B for large radius
        c.rgb *= pow(clamp(abs(dist - rad) / rad, 0., 1.), shadow);
    return c;
}
