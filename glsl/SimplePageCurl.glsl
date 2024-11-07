// Name: SimplePageCurl
// Author: Andrew Hung
// License: MIT
// Adapted by Raymond Luckhurst
// see simple page curl effect by Andrew Hung, https://www.shadertoy.com/view/ls3cDB
// and https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/

const float M_PI = 3.14159265359;

uniform int angle; // = 80
uniform float radius; // = 0.15
uniform bool roll; // = false
uniform bool uncurl; // = false
uniform bool greyback; // = false
uniform float opacity; // = 0.8
uniform float shadow; // = 0.2

vec4 transition (vec2 uv) {
    // setup
    float phi = radians(float(angle)) - M_PI / 2.; // target curl angle
    vec2 dir = normalize(vec2(cos(phi) * ratio, sin(phi))); // direction unit vector
    vec2 q = vec2((dir.x >= 0.) ? 0.5 : -0.5, (dir.y >= 0.) ? 0.5 : -0.5); // quadrant corner
    vec2 i = dir * dot(q, dir); // initial position, curl axis on corner
    vec2 f = -(i + dir * radius * 2.); // final position, curl & shadow just out of view
    vec2 m = f - i; // path extent, perpendicular to curl axis

    // get point relative to curl axis
    vec2 p = i + m * (uncurl ? 1. - progress : progress); // current axis point from origin
    q = uv - .5; // distance of current point from centre
    float dist = dot(q - p, dir); // distance of point from curl axis
    p = q - dir * dist; // point perpendicular to curl axis

    // map point to curl
    vec4 a = getFromColor(uv), b = getToColor(uv), c = uncurl ? a : b;
    bool g = false, o = false, s = false; // getcolor & opacity & shadow flags
    if (dist < 0.) { // point is over flat or rolling A
        if (!roll) { // curl
            p += dir * (M_PI * radius - dist) + .5;
            g = true;
        } else if (-dist < radius) { // possibly on roll over
            phi = asin(-dist / radius);
            p += dir * (M_PI + phi) * radius + .5;
            g = s = true;
        }
        if (g && p.x >= 0. && p.x <= 1. && p.y >= 0. && p.y <= 1.) // on back of A
            o = true;
        else
            c = uncurl ? b : a, g = false;
    } else if (radius > 0.) { // point is over curling A or flat B
        // map to cylinder point
        phi = asin(dist / radius);
        vec2 p2 = p + dir * (M_PI - phi) * radius + .5;
        vec2 p1 = p + dir * phi * radius + .5;
        if (p2.x >= 0. && p2.x <= 1. && p2.y >= 0. && p2.y <= 1.) // on curling back of A
            p = p2, g = o = s = true;
        else if (p1.x >= 0. && p1.x <= 1. && p1.y >= 0. && p1.y <= 1.) // on curling front of A
            p = p1, g = true;
        else // on B
            s = true;
    }
    if (g) // on A
        c = uncurl ? getToColor(p) : getFromColor(p);
    if (o) { // need opacity
        if (greyback)
            c.rgb = vec3((c.r + c.b + c.g) / 3.);
        c.rgb += (1. - c.rgb) * opacity;
    }
    if (s && radius > 0.) // need shadow
        // TODO: ok over A, makes a tideline over B for large radius
        c.rgb *= pow(clamp(abs(dist + (g ? radius : -radius)) / radius, 0., 1.), shadow);
    return c;
}
