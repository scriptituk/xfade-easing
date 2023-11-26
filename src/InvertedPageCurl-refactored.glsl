// author: Hewlett-Packard
// license: BSD 3 Clause
// Adapted by Sergey Kosarevsky from:
// http://rectalogic.github.io/webvfx/examples_2transition-shader-pagecurl_8html-example.html
// Refactored by Raymond Luckhurst to aid porting to FFmpeg Xfade

const float MIN_AMOUNT = -0.16;
const float MAX_AMOUNT = 1.5;
float amount = progress * (MAX_AMOUNT - MIN_AMOUNT) + MIN_AMOUNT;

const float PI = 3.141592653589793;

// const float scale = 512.0;
// const float sharpness = 3.0;

float cylinderCenter = amount;
float cylinderAngle = 2.0 * PI * amount; // 360 degrees * amount

const float cylinderRadius = 1.0 / 2.0 / PI;

const float angle = 100.0 * PI / 180.0;
const float C = cos(angle);
const float S = sin(angle);

/* (antiAlias deactivated to simplify implementation)
vec4 antiAlias(vec4 color1, vec4 color2, float distanc) {
    distanc *= scale;
    if (distanc < 0.0) return color2;
    if (distanc > 2.0) return color1;
    float dd = pow(1.0 - distanc / 2.0, sharpness);
    return ((color2 - color1) * dd) + color1;
}
*/

float distanceToEdge(vec2 point) { // inline this func
    float dx, dy;
    if (point.x < 0.0) dx = -point.x;
    else if (point.x > 1.0) dx = point.x - 1.0;
    else if (point.x > 0.5) dx = 1.0 - point.x;
    else dx = point.x;
    if (point.y < 0.0) dy = -point.y;
    else if (point.y > 1.0) dy = point.y - 1.0;
    else if (point.y > 0.5) dy = 1.0 - point.y;
    else dy = point.y;
    return ((point.x >= 0.0 && point.x <= 1.0) || (point.y >= 0.0 && point.y <= 1.0)) ? min(dx, dy) : sqrt(dx * dx + dy * dy);
}

vec4 transition(vec2 p) {
    vec4 colour;
    float hitAngle;
    float shado;
    vec2 point = vec2(C * p.x + S * p.y - 0.801, -S * p.x + C * p.y + 0.89); // rotation
    float yc = point.y - cylinderCenter;

    if (yc > cylinderRadius) { // Flat surface
        colour = getFromColor(p);
    } else if (yc < -cylinderRadius) { // Behind surface
        yc = -cylinderRadius - cylinderRadius - yc;
        hitAngle = acos(yc / cylinderRadius) + cylinderAngle - PI;
        point.y = hitAngle / 2.0 / PI;
        point = vec2(C * point.x - S * point.y + 0.985, S * point.x + C * point.y + 0.985); // rrotation
        if (yc < 0.0 && point.x >= 0.0 && point.x <= 1.0 && point.y >= 0.0 && point.y <= 1.0 && (hitAngle < PI || amount > 0.5)) {
            shado = 1.0 - sqrt(pow(point.x - 0.5, 2.0) + pow(point.y - 0.5, 2.0)) / (71.0 / 100.0);
            shado *= pow(-yc / cylinderRadius, 3.0);
            shado *= 0.5;
        } else {
            shado = 0.0;
        }
        colour = vec4(getToColor(p).rgb - shado, 1.0);
    } else {
        // seeThrough
        hitAngle = PI - acos(yc / cylinderRadius) + cylinderAngle;
        if (yc > 0.0) {
            colour = getFromColor(p);
        } else {
            vec2 pt = point; // rotation
            pt.y = hitAngle / 2.0 / PI;
            pt = vec2(C * pt.x - S * pt.y + 0.985, S * pt.x + C * pt.y + 0.985); // rrotation
            if (pt.x >= 0.0 && pt.x <= 1.0 && pt.y >= 0.0 && pt.y <= 1.0) {
                colour = getFromColor(pt);
//              colour = antiAlias(colour, vec4(0.0), distanceToEdge(pt));
            } else {
                colour = getToColor(p);
            }
        }

        hitAngle = cylinderAngle + cylinderAngle - hitAngle;
        float hitAngleMod = mod(hitAngle, 2.0 * PI);
        if (!(hitAngleMod > PI && amount < 0.5) && !(hitAngleMod > PI/2.0 && amount < 0.0)) { // seeThroughWithShadow
            point.y = hitAngle / 2.0 / PI;
            point = vec2(C * point.x - S * point.y + 0.985, S * point.x + C * point.y + 0.985); // rrotation
            float dist = distanceToEdge(point); // (inline)
            shado = (1.0 - dist * 30.0) / 3.0;
            if (shado < 0.0)
                shado = 0.0;
            else
                shado *= amount;
            colour.r -= shado;
            colour.g -= shado;
            colour.b -= shado;
            if (point.x >= 0.0 && point.x <= 1.0 && point.y >= 0.0 && point.y <= 1.0) {
                // backside
                vec4 back = getFromColor(point), otherColor;
                float gray = (back.r + back.b + back.g) / 15.0;
                gray += 0.8 * (pow(1.0 - abs(yc / cylinderRadius), 0.2) / 2.0 + 0.5);
                back.rgb = vec3(gray);
/*
                if (yc < 0.0) {
                    shado = 1.0 - (sqrt(pow(point.x - 0.5, 2.0) + pow(point.y - 0.5, 2.0)) / 0.71);
                    shado *= pow(-yc / cylinderRadius, 3.0);
                    shado *= 0.5;
                    otherColor = vec4(0.0, 0.0, 0.0, shado);
                } else {
                    otherColor = getFromColor(p);
                }
                back = antiAlias(back, otherColor, cylinderRadius - abs(yc));
                colour = antiAlias(back, colour, dist);
*/              colour = back;
            }
        }
    }

    return colour;
}
