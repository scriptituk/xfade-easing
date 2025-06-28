// FFmpeg XFade easing and extensions by Raymond Luckhurst, Scriptit UK, https://scriptit.uk
// GitHub: owner scriptituk; repository xfade-easing; https://github.com/scriptituk/xfade-easing
//
// This is a port of standard easing equations and CSS easing functions for the FFmpeg XFade filter
// It also ports extended transitions, notably GLSL transitions, for use with or without easing
//
// See https://github.com/scriptituk/xfade-easing for documentation

#include <stdbool.h>
#include <float.h>
#include <ctype.h>
#include "libavfilter/version.h"
#include "libavutil/avstring.h"
#include "libavutil/mem.h"
#include "libavutil/mem_internal.h"
#include "libavutil/parseutils.h"

////////////////////////////////////////////////////////////////////////////////
// definitions & prototypes
////////////////////////////////////////////////////////////////////////////////

#define P5f 0.5f /* ubiquitous point 5 float */
#define M_1_2PIf (M_1_PIf * P5f) /* 1/(2*pi) */
#define M_2PIf (M_PIf + M_PIf) /* 2*pi */

static int xe_error(void *avcl, const char *fmt, ...);
static void xe_warning(void *avcl, const char *fmt, ...);
static void xe_debug(void *avcl, const char *fmt, ...);

////////////////////////////////////////////////////////////////////////////////
// aggregate types
////////////////////////////////////////////////////////////////////////////////

// reverse option bit flags
typedef enum { REVERSE_TRANSITION = 1, REVERSE_EASING = 2 } ReverseOpts;

// blend modes
typedef enum {
    NORMAL, MULTIPLY, SCREEN, OVERLAY, DARKEN, LIGHTEN, COLORDODGE, COLORBURN,
    HARDLIGHT, SOFTLIGHT, DIFFERENCE, EXCLUSION, HUE, SATURATION, COLOR, LUMINOSITY
} BlendMode;

// integer pair
typedef struct {
    int x, y;
} ivec2;

// normalised pixel coordinates
typedef struct {
    float x, y;
} vec2;

// normalised plane data
typedef union {
    DECLARE_ALIGNED(64, float, p)[4];
    struct { float p0, p1, p2, p3; };
} vec4;

// easing arguments
typedef struct {
    enum { STANDARD, LINEAR, BEZIER, STEPS } type; // easing type
    union {
        struct Standard { // Robert Penner & supplementary easings
            enum { EASE_INOUT, EASE_IN, EASE_OUT } mode;
        } e;
        struct Linear { // CSS linear
            int stops;
            vec2 *points; // alloc
        } l;
        union Bezier { // CSS cubic-bezier
            struct { float x1, y1, x2, y2; };
            float p[4];
        } b;
        struct Steps { // CSS steps
            int steps;
            enum { JUMP_START, JUMP_END, JUMP_NONE, JUMP_BOTH } position;
        } s;
    };
} EasingArgs;

// extended transition arguments
typedef struct {
    int argc;
    struct Argv {
        char *param; // optional name
        double value;
    } *argv; // alloc
} XTransitionArgs;

// xfade-easing context (member of XFadeContext)
struct XTransition;
typedef struct XFadeEasingContext {
    float (*easingf)(const struct XFadeEasingContext *k, float progress);
    vec4 (*xtransitionf)(const struct XTransition *e);
    EasingArgs eargs;
    XTransitionArgs targs;
    double tdata[20]; // transition parameters and constants
    float framerate;
    float duration; // seconds
    float r; // frame aspect ratio
    int n; // number of planes
    int mw, mh; // maximum width, height
    int mv; // maximum pixel value
    bool is_rgb; // pixel format is RGB type
    bool is_16; // pixel depth > 8
    bool init; // true when initialised
    const struct XFadeContext *s; // the XFadeContext
} XFadeEasingContext;

// transition thread data (unit intervals) modelled on GL Transition Specification v1
typedef struct XTransition {
    float progress; // transition progress, 0.0 to 1.0 (cf. P)
    float ratio; // frame width / height (cf. W / H)
    vec2 p; // pixel position, .y==0 is bottom (cf. X, Y)
    vec4 a, b; // plane data at p (cf. A, B)
    const struct XFadeEasingContext *k; // the XFadeEasingContext
} XTransition;

////////////////////////////////////////////////////////////////////////////////
// easing functions
////////////////////////////////////////////////////////////////////////////////

// standard easings --------------------------------------------------

static float rp_quadratic(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return t * t;
    if (mode == EASE_OUT) return (2 - t) * t;
    return (t < P5f) ? t * t * 2 : (2 - t) * t * 2 - 1;
}

static float rp_cubic(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return t * t * t;
    if (mode == EASE_OUT) return --t, t * t * t + 1;
    return (t < P5f) ? (t * t * t * 4) : (--t, t * t * t * 4 + 1);
}

static float rp_quartic(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return t *= t, t * t;
    if (mode == EASE_OUT) return --t, t *= t, 1 - t * t;
    return (t < P5f) ? (t *= t, t * t * 8) : (--t, t *= t, t * t * -8 + 1);
}

static float rp_quintic(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    float s;
    if (mode == EASE_IN) return s = t, t *= t, t * t * s;
    if (mode == EASE_OUT) return s = --t, t *= t, t * t * s + 1;
    return (t < P5f) ? (s = t, t *= t, t * t * s * 16) : (s = --t, t *= t, t * t * s * 16 + 1);
}

static float rp_sinusoidal(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return 1 - cosf(t * M_PI_2f);
    if (mode == EASE_OUT) return sinf(t * M_PI_2f);
    return (1 - cosf(t * M_PIf)) / 2;
}

static float rp_exponential(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (t <= 0 || t >= 1) return t > P5f;
    if (mode == EASE_IN) return exp2f((t - 1) * 10);
    if (mode == EASE_OUT) return 1 - exp2f(t * -10);
    return (t < P5f) ? exp2f(20 * t - 11) : 1 - exp2f(9 - 20 * t);
}

static float rp_circular(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return 1 - sqrtf(1 - t * t);
    if (mode == EASE_OUT) return sqrtf((2 - t) * t);
    return (t < P5f) ? (1 - sqrtf(1 - t * t * 4)) / 2 : (--t, (1 + sqrtf(1 - t * t * 4)) / 2);
}

static float rp_elastic(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return --t, cosf(t * (M_PIf * 20.f / 3)) * exp2f(10 * t);
    if (mode == EASE_OUT) return 1 - cosf(t * (M_PIf * 20.f / 3)) / exp2f(10 * t);
    float p = t + t - 1, c = cosf(p * (M_PIf * 40.f / 9)) / 2; p = exp2f(10 * p);
    return (t < P5f) ? c * p : 1 - c / p;
}

static float rp_back(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    float r = 1 - t, b = 1.70158f; // for 10% back
    if (mode == EASE_IN) return t * t * (t * (b + 1) - b);
    if (mode == EASE_OUT) return 1 - r * r * (r * (b + 1) - b);
    b *= 1.525f;
    return (t < P5f) ? t * t * (t * (b + 1) * 2 - b) * 2
                     : 1 - r * r * (r * (b + 1) * 2 - b) * 2;
}

static float rp_bounce(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    float c, s = (t < P5f) ? 1 : -1;
    if (mode == EASE_IN) t = 1 - t;
    else if (mode == EASE_INOUT) t = (1 - t - t) * s;
    if (t < 4.f / 11.f)                         c = 0;
    else if (t < 8.f / 11.f)  t -= 6.f / 11.f,  c = 3.f / 4.f;
    else if (t < 10.f / 11.f) t -= 9.f / 11.f,  c = 15.f / 16.f;
    else                      t -= 21.f / 22.f, c = 63.f / 64.f;
    t = 121.f / 16.f * t * t + c;
    if (mode == EASE_IN) return 1 - t;
    if (mode == EASE_OUT) return t;
    return (1 - t * s) / 2;
}

// supplementary easings --------------------------------------------------

static float se_squareroot(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return sqrtf(t);
    if (mode == EASE_OUT) return 1 - sqrtf(1 - t);
    return (t < P5f) ? sqrtf(t + t) / 2 : 1 - sqrtf(2 - t - t) / 2;
}

static float se_cuberoot(const XFadeEasingContext *k, float t)
{
    const int mode = k->eargs.e.mode;
    if (mode == EASE_IN) return cbrtf(t);
    if (mode == EASE_OUT) return 1 - cbrtf(1 - t);
    return (t < P5f) ? cbrtf(t + t) / 2 : 1 - cbrtf(2 - t - t) / 2;
}

// CSS easings --------------------------------------------------

// see https://drafts.csswg.org/css-easing-2/
// WebKit: https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/animation/TimingFunction.cpp
// Gecko: https://github.com/mozilla/gecko-dev/blob/master/servo/components/style/piecewise_linear.rs
static float css_linear(const XFadeEasingContext *k, float t)
{
    const struct Linear *a = &k->eargs.l;
    vec2 *p = a->points;
    int i, n = a->stops;
    if (n == 0)
        return t;
    if (n == 1) // ? see https://searchfox.org/mozilla-central/source/servo/components/style/piecewise_linear.rs
        return 1 - p[0].y; // y is constant (I can't see this in the spec)
    for (i = n - 1; i; i--)
        if (p[i].x <= t)
            break;
    if (i < 0)
        i = 0;
    else if (i == n - 1)
        --i;
    p += i;
    if (p[1].x - p[0].x < FLT_EPSILON) // nearly equal
        return p[1].y;
    return p[0].y + (t - p[0].x) / (p[1].x - p[0].x) * (p[1].y - p[0].y);
}

// see https://drafts.csswg.org/css-easing-2/
// see https://cubic-bezier.com/
// see solve_cubic_bezier() at end of this file
// WebKit: https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/animation/TimingFunction.cpp
static float solve_cubic_bezier(float x1, float y1, float x2, float y2, float x, float epsilon);
static float css_cubic_bezier(const XFadeEasingContext *k, float t)
{
    const union Bezier *a = &k->eargs.b;
    float epsilon = 1 / (1000 * k->duration); // as per TimingFunction.cpp
    return solve_cubic_bezier(a->x1, a->y1, a->x2, a->y2, t, epsilon); // licensed code
}

// see https://drafts.csswg.org/css-easing-2/
// WebKit: https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/animation/TimingFunction.cpp
static float css_steps(const XFadeEasingContext *k, float t)
{
    const struct Steps *a = &k->eargs.s;
    bool before = 0; // TODO: CSS before flag, if needed
    int n = a->steps, s = floorf(t * n);
    if (a->position == JUMP_START || a->position == JUMP_BOTH)
        ++s;
    if (before && !fmodf(t * n, 1))
        s--;
    if (t >= 0 && s < 0)
        s = 0;
    if (a->position == JUMP_NONE)
        --n;
    else if (a->position == JUMP_BOTH)
        ++n;
    if (t <= 1 && s > n)
        s = n;
    return (float)s / n;
}

////////////////////////////////////////////////////////////////////////////////
// extended transitions
////////////////////////////////////////////////////////////////////////////////

// FF functions:
// mix() fract() smoothstep()(clamped) in libavfilter/vf_xfade.c
// av_strtod() in libavutil/eval.c
// av_parse_color() in libavutil/parseutils.h
// av_clip*() in libavutil/common.h
// av_str*() in libavutil/avstring.h
// various in libavutil/mem.h libavutil/log.h
// FFDIFFSIGN in libavutil/macros.h

#define IVEC2(i, j) ((ivec2) { .x = (i), .y = (j) })
#define VEC2(i, j) ((vec2) { .x = (i), .y = (j) })
#define VEC3(i, j, k) ((vec4) { .p0 = (i), .p1 = (j), .p2 = (k) }) /* omit alpha */
#define VEC4(i, j, k, a) ((vec4) { .p0 = (i), .p1 = (j), .p2 = (k), .p3 = (a) })

#define sign(x) FFDIFFSIGN((x), 0)

// scalar functions --------------------------------------------------

static inline float degrees(float a) { return a * 180 / M_PIf; }
static inline float radians(float a) { return a / 180 * M_PIf; }
static inline float glmod(float x, float y) { return x - y * floorf(x / y); } // C fmod uses trunc
static inline int step(float edge, float x) { return (x < edge) ? 0 : 1; }
static inline float lerp(float x, float y, float z) { return x + (y - x) * z; }
static inline float mixf(float a, float b, float m) { return mix(b, a, m); } // vf_xfade.c mix() args are swapped
static inline bool betweenf(float x, float min, float max) { return x >= min && x <= max; }
static inline bool betweenUI(float x) { return betweenf(x, 0, 1); } // within unit interval
static inline float clipUI(float x) { return av_clipf(x, 0, 1); } // clip to unit interval
static inline float frandf(float x, float y)
{
    return fract(sinf(x * 12.9898f + y * 78.233f) * 43758.5453f);
//  return fract(sin(x * 12.9898 + y * 78.233) * 43758.5453); // doubles render like GL Transitions
}
static inline float r2f(AVRational r) { return r.num / (float)r.den; } // cf. av_q2d()

// coordinate functions --------------------------------------------------

static inline vec2 vec2f(float f) { return VEC2(f, f); }
static inline vec2 vec2i(ivec2 p) { return VEC2(p.x, p.y); } // as float
static inline vec2 flip2(vec2 p) { return VEC2(p.y, p.x); }
static inline vec2 add2f(vec2 p, float f) { return VEC2(p.x + f, p.y + f); }
static inline vec2 sub2f(vec2 p, float f) { return VEC2(p.x - f, p.y - f); }
static inline vec2 mul2f(vec2 p, float f) { return VEC2(p.x * f, p.y * f); }
static inline vec2 div2f(vec2 p, float f) { return mul2f(p, 1 / f); }
static inline vec2 add2(vec2 a, vec2 b) { return VEC2(a.x + b.x, a.y + b.y); }
static inline vec2 sub2(vec2 a, vec2 b) { return VEC2(a.x - b.x, a.y - b.y); }
static inline vec2 mul2(vec2 a, vec2 b) { return VEC2(a.x * b.x, a.y * b.y); }
static inline vec2 div2(vec2 a, vec2 b) { return VEC2(a.x / b.x, a.y / b.y); }
static inline vec2 abs2(vec2 p) { return VEC2(fabsf(p.x), fabsf(p.y)); }
static inline vec2 floor2(vec2 p) { return VEC2(floorf(p.x), floorf(p.y)); }
static inline vec2 fract2(vec2 p) { return VEC2(fract(p.x), fract(p.y)); }
static inline vec2 mix2(vec2 a, vec2 b, float m) { return add2(mul2f(a, 1 - m), mul2f(b, m)); }
static inline vec2 mod2(vec2 p, float f) { return VEC2(glmod(p.x, f), glmod(p.y, f)); }
static inline vec2 rcp2(vec2 p) { return VEC2(1 / p.x, 1 / p.y); }
static inline vec2 sign2(vec2 p) { return VEC2(sign(p.x), sign(p.y)); }
static inline float asum2(vec2 p) { return fabsf(p.x) + fabsf(p.y); }
static inline float atn2(vec2 p) { return atan2f(p.y, p.x); }
static inline float frand2(vec2 p) { return frandf(p.x, p.y); }
static inline float length2(vec2 p) { return hypotf(p.x, p.y); }
static inline float distance2(vec2 a, vec2 b) { return length2(sub2(a, b)); }
static inline float dot2(vec2 a, vec2 b) { return a.x * b.x + a.y * b.y; }
static inline vec2 normalize2(vec2 p) { return div2f(p, length2(p)); }
static inline vec2 cossin2(float a) { return VEC2(cosf(a), sinf(a)); } // cf. sincosf()
static inline vec2 rot2(vec2 p, float a) // clockwise
{
    vec2 q = cossin2(a);
    return VEC2(p.x * q.x + p.y * q.y, p.y * q.x - p.x * q.y);
}
static inline bool between2(vec2 p, float min, float max)
{
    return fminf(p.x, p.y) >= min && fmaxf(p.x, p.y) <= max;
}
static inline bool betweenUI2(vec2 p) { return between2(p, 0, 1); }

// colour functions --------------------------------------------------

static inline vec4 vec4f(float f) { return VEC4(f, f, f, f); }
static inline vec4 mul4f(vec4 c, float f) { return VEC4(c.p0 * f, c.p1 * f, c.p2 * f, c.p3 * f); }
static inline vec4 add4(vec4 a, vec4 b) { return VEC4(a.p0 + b.p0, a.p1 + b.p1, a.p2 + b.p2, a.p3 + b.p3); }
static inline vec4 sub4(vec4 a, vec4 b) { return VEC4(a.p0 - b.p0, a.p1 - b.p1, a.p2 - b.p2, a.p3 - b.p3); }
static inline vec4 mix4(vec4 a, vec4 b, float m) { return add4(mul4f(a, 1 - m), mul4f(b, m)); }
static inline vec4 clipUI4(vec4 c) { return VEC4(clipUI(c.p0), clipUI(c.p1), clipUI(c.p2), clipUI(c.p3)); }

static inline vec4 vec3f(float f) { return VEC3(f, f, f); }
static inline vec4 add3f(vec4 c, float f) { return VEC3(c.p0 + f, c.p1 + f, c.p2 + f); }
static inline vec4 sub3f(vec4 c, float f) { return VEC3(c.p0 - f, c.p1 - f, c.p2 - f); }
static inline vec4 mul3f(vec4 c, float f) { return VEC3(c.p0 * f, c.p1 * f, c.p2 * f); }
static inline vec4 div3f(vec4 c, float f) { return mul3f(c, 1 / f); }
static inline vec4 add3(vec4 a, vec4 b) { return VEC3(a.p0 + b.p0, a.p1 + b.p1, a.p2 + b.p2); }
static inline vec4 sub3(vec4 a, vec4 b) { return VEC3(a.p0 - b.p0, a.p1 - b.p1, a.p2 - b.p2); }
static inline vec4 cpl3(vec4 c) { return VEC3(1 - c.p0, 1 - c.p1, 1 - c.p2); } // complement unit interval
static inline vec4 abs3(vec4 c) { return VEC3(fabsf(c.p0), fabsf(c.p1), fabsf(c.p2)); }
static inline vec4 fract3(vec4 c) { return VEC3(fract(c.p0), fract(c.p1), fract(c.p2)); }
static inline vec4 sqrt3(vec4 c) { return VEC3(sqrtf(c.p0), sqrtf(c.p1), sqrtf(c.p2)); }
static inline float min3(vec4 c) { return fminf(fminf(c.p0, c.p1), c.p2); }
static inline float max3(vec4 c) { return fmaxf(fmaxf(c.p0, c.p1), c.p2); }
static inline float dot3(vec4 a, vec4 b) { return a.p0 * b.p0 + a.p1 * b.p1 + a.p2 * b.p2; }
static inline float length3(vec4 c) { return sqrtf(dot3(c, c)); }
static inline vec4 normalize3(vec4 c) { return div3f(c, length3(c)); }

// colour conversion --------------------------------------------------

// convert GBR to YUV standard-definition BT.601
// TODO: support high-definition BT.709 too?
// see https://en.wikipedia.org/wiki/YCbCr#ITU-R_BT.601_conversion
static const vec4 Od = {{ 16./255, 128./255, 128./255, 0 }}; // digital headroom/toeroom offsets
static inline vec4 gbr2yuv(vec4 c)
{
    // BT.601 matrix                G            B            R
    static const vec4 Y = {{ 128.553/255,  24.966/255,  65.481/255 }},
                      U = {{ -74.203/255,    112./255, -37.797/255 }},
                      V = {{ -93.786/255, -18.214/255,    112./255 }};
    return add4(VEC4(dot3(c, Y), dot3(c, U), dot3(c, V), c.p3), Od);
}

// convert YUV to GBR
static inline vec4 yuv2gbr(vec4 c)
{
    // inverse BT.601 matrix
    #define BU 255./224*1.772
    #define RV 255./224*1.402
    static const float Bu = BU, Rv = RV, Gy = 255./219, Gu = -0.114/0.587*BU, Gv = -0.299/0.587*RV;
    c = sub4(c, Od);
    float y = c.p0 * Gy; // Y G=B=R
    return VEC4(y + c.p1 * Gu + c.p2 * Gv, y + c.p1 * Bu, y + c.p2 * Rv, c.p3);
}

// blending --------------------------------------------------

// see https://www.w3.org/TR/compositing-1/#blending
// see https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=322

static inline float normal(float b, float f) { return f; }
static inline float multiply(float b, float f) { return b * f; }
static inline float screen(float b, float f) { return b + f - b * f; }
static inline float darken(float b, float f) { return fminf(b, f); }
static inline float lighten(float b, float f) { return fmaxf(b, f); }
static inline float colordodge(float b, float f) { return (b <= 0) ? 0 : (f >= 1) ? 1 : fminf(1, b / (1 - f)); }
static inline float colorburn(float b, float f) { return (b >= 1) ? 1 : (f <= 0) ? 0 : 1 - fminf(1, (1 - b) / f); }
static inline float hardlight(float b, float f) { return (f <= P5f) ? multiply(b, f + f) : screen(b, f + f - 1); }
static inline float overlay(float b, float f) { return hardlight(f, b); }
static inline float difference(float b, float f) { return fabsf(b - f); }
static inline float exclusion(float b, float f) { return b + f - b * f * 2; }
static inline float softlight(float b, float f) {
    bool l = f <= P5f;
    float m = l ? b : 1, d = l ? 1 : (b <= 0.25f) ? ((b * 16 - 12) * b + 4) * b : sqrtf(b); // fmaf?
    return b + (f + f - 1) * m * (d - b);
}

static inline float lum3(vec4 c) { return dot3(c, VEC3(0.587f, 0.114f, 0.299f)); } // Rec. 601
static inline float sat3(vec4 c) { return max3(c) - min3(c); }

static vec4 lum3f(vec4 c, float l) { // set luminance
    c = add3f(c, l - lum3(c));
    // scale luminance
    float n = min3(c), x = max3(c);
    l = lum3(c);
    if (n < 0)
        c = add3f(mul3f(sub3f(c, l), l / (l - n)), l);
    if (x > 1)
        c = add3f(mul3f(sub3f(c, l), (1 - l) / (x - l)), l);
    return c;
}

static vec4 sat3f(vec4 c, float s) { // set saturation
    float *p = c.p;
    // sort into component value order: min mid max
    int o[] = {0, 1, 2};
    if (p[0] > p[1])
        o[1] = 0, o[0] = 1;
    if (p[o[1]] > c.p2) {
        o[2] = o[1], o[1] = 2;
        if (p[o[0]] > p[o[1]])
            o[1] = o[0], o[0] = 2;
    }
    // scale saturation
    float *n = &p[o[0]], *d = &p[o[1]], *x = &p[o[2]];
    if (*x > *n)
        *d = (*d - *n) * s / (*x - *n), *x = s;
    else
        *d = *x = 0;
    *n = 0;
    return c;
}

// composite background, foreground & blended colours with alpha
// this is the colour compositing formula from PDF32000_2008.pdf 11.3.6 but simplified
// see https://stackoverflow.com/questions/40796852/mix-two-non-opaque-colors-with-hue-blend-mode/40962043
static inline float comp(float c, float d, float f, float r, float b) { return fmaf(fmaf(c, d, f), r, b); }
static vec4 composite(vec4 b, vec4 f, vec4 c) { // bg, fg, blended
    float a = f.p3 + b.p3 - f.p3 * b.p3; // resulting alpha
    float r = f.p3 / a;
    c = sub3(c, f);
    f = sub3(f, b);
    return VEC4(comp(c.p0, b.p3, f.p0, r, b.p0),
                comp(c.p1, b.p3, f.p1, r, b.p1),
                comp(c.p2, b.p3, f.p2, r, b.p2),
                a);
}

// blend background & foreground colours
// see https://www.w3.org/TR/compositing-1/#blending
static vec4 blend(const XTransition *e, vec4 b, vec4 f, BlendMode mode) { // bg, fg, mode
    vec4 c;
    if (!e->k->is_rgb)
        b = yuv2gbr(b), f = yuv2gbr(f);
    #define BLEND3(n) VEC3(n(b.p0, f.p0), n(b.p1, f.p1), n(b.p2, f.p2))
    switch (mode) {
        default:         c = BLEND3(normal); break; // NORMAL
        case MULTIPLY:   c = BLEND3(multiply); break;
        case SCREEN:     c = BLEND3(screen); break;
        case OVERLAY:    c = BLEND3(overlay); break;
        case DARKEN:     c = BLEND3(darken); break;
        case LIGHTEN:    c = BLEND3(lighten); break;
        case COLORDODGE: c = BLEND3(colordodge); break;
        case COLORBURN:  c = BLEND3(colorburn); break;
        case HARDLIGHT:  c = BLEND3(hardlight); break;
        case SOFTLIGHT:  c = BLEND3(softlight); break;
        case DIFFERENCE: c = BLEND3(difference); break;
        case EXCLUSION:  c = BLEND3(exclusion); break;
        case HUE:        c = lum3f(sat3f(f, sat3(b)), lum3(b)); break;
        case SATURATION: c = lum3f(sat3f(b, sat3(f)), lum3(b)); break;
        case COLOR:      c = lum3f(f, lum3(b)); break;
        case LUMINOSITY: c = lum3f(b, lum3(f)); break;
    }
    c = composite(b, f, c);
    c = clipUI4(c);
    if (!e->k->is_rgb)
        c = gbr2yuv(c);
    return c;
}

// get/set pixel data --------------------------------------------------

// scale unit interval to clipped integer
// see https://stackoverflow.com/questions/1914115/converting-color-value-from-float-0-1-to-byte-0-255
static inline int scaleUI(float val, int max) { return av_clip(val * max + P5f, 0, max); } // trunc rounded

// get pointer to line of plane data at y
static inline uint8_t *line1(const AVFrame *f, int p, int y) { return f->data[p] + y * f->linesize[p]; }
static inline uint16_t *line2(const AVFrame *f, int p, int y) { return (uint16_t*) line1(f, p, y); }

#define _getFromColor1(v) getColor(e, v.x, v.y, 0)
#define _getFromColor2(x, y) getColor(e, (x), (y), 0)
#define _getFromColorVA(_1,_2,NAME,...) NAME
#define getFromColor(...) _getFromColorVA(__VA_ARGS__, _getFromColor2, _getFromColor1)(__VA_ARGS__)
#define _getToColor1(v) getColor(e, v.x, v.y, 1)
#define _getToColor2(x, y) getColor(e, (x), (y), 1)
#define _getToColorVA(_1,_2,NAME,...) NAME
#define getToColor(...) _getToColorVA(__VA_ARGS__, _getToColor2, _getToColor1)(__VA_ARGS__)

// get from/to colour at pixel point
static av_noinline vec4 getColor(const XTransition *e, float x, float y, int nb) // cf. vf_xfade.c getpix()
{
    const XFadeEasingContext *k = e->k;
    const XFadeContext *s = k->s;
    const AVFrame *f = s->xf[nb ^ (s->reverse & REVERSE_TRANSITION)];
    const int i = scaleUI(x, k->mw), j = scaleUI(1 - y, k->mh), n = k->n;
    const float mv = k->mv;
    // nb_planes is always 1, 3 or 4
    // nb_planes = 1: (gray/mono) processed as YUV so set u,v to 0.5
    // nb_planes < 4: (opaque) set alpha to 1
    vec4 c = { .p1 = P5f, .p2 = P5f, .p3 = 1 }; // default plane values
    int p = 0;
    if (k->is_16)
        do
            c.p[p] = line2(f, p, j)[i] / mv;
        while (++p < n);
    else
        do
            c.p[p] = line1(f, p, j)[i] / mv;
        while (++p < n);
    return c;
}

// transition arguments --------------------------------------------------

// convert colour arg to plane data
//  value > 1 is RGBA (argv() parser below adds 1^32 for colours)
//  0 <= value <= 1 is opaque greyscale
//  value < -1 is a texture type
//  -1 <= value < 0 is fully transparent greyscale
static vec4 texture(const XTransition *e, int type); // delegate
static vec4 colourArg(const XTransition *e, double value)
{
    const XFadeEasingContext *k = e->k;
    bool s = signbit(value); // for neg zero
    vec4 c;
    if (value > 1) { // RGBA
        uint32_t rgba = value; // packed RGBA (clips bit 32 colour flag)
        uint8_t r = rgba >> 24, g = rgba >> 16, b = rgba >> 8, a = rgba;
        c = VEC4(g / 255.f, b / 255.f, r / 255.f, a / 255.f); // normalised GBRA
        if (!k->is_rgb)
            c = gbr2yuv(c); // normalised YUVA
    } else if (value <= -2) { // texture
        int type = value; // texture type (trunc)
        c = texture(e, type); // create texture
        if (!k->is_rgb)
            c = gbr2yuv(c);
    } else { // greyscale
        float grey = s ? clipUI(-value) : value;
        float p12 = k->is_rgb ? grey : P5f;
        c = VEC4(grey, p12, p12, !s); // opaque/transparent
    }
    if (!k->init) { // initialising
        const char *t = (value < -1) ? "texture"
                      : s ? "transparent"
                      : (value <= 1) ? "grey"
                      : k->is_rgb ? "gbra" : "yuva";
        if (value <= -2) { // texture
            xe_debug(NULL, "colour: %s = %d\n", t, (int)value);
        } else if (value <= 1 || k->is_rgb) { // transparent/greyscale/RGBA
            xe_debug(NULL, "colour: %s = %g %g %g %g\n", t, c.p0, c.p1, c.p2, c.p3);
        } else { // YUVA
            vec4 d = yuv2gbr(c); // test conversions
            int v[4]; for (int i = 0; i < 4; i++) v[i] = scaleUI(d.p[i], 255);
            xe_debug(NULL, "colour: %s = %g %g %g %g (#%02X%02X%02X%02X)\n",
                     t, c.p0, c.p1, c.p2, c.p3, v[2], v[0], v[1], v[3]);
        }
    }
    return c;
}

// simple caching of transition constants
#define INIT if (!e->k->init)
#define INIT_BEGIN int argi = 0;
#define INIT_END INIT return (vec4){{0}};
#define ARG1(type, param, def) \
    argi++; INIT arg(e->k, argi-1, #type, #param, def); \
    const type param = e->k->tdata[argi-1];
#define ARG2(type, param, defx, defy) \
    argi+=2; INIT arg(e->k, argi-2, #type, #param ".x", defx), arg(e->k, argi-1, #type, #param ".y", defy); \
    const type param = (type) { e->k->tdata[argi-2], e->k->tdata[argi-1] };
#define ARG4(type, param, def) \
    argi++; INIT arg(e->k, argi-1, #type, #param, def); \
    const type param = colourArg(e, e->k->tdata[argi-1]);
#define VAR1(type, param, val) \
    argi++; INIT var(e->k, argi-1, val); \
    const type param = e->k->tdata[argi-1];
#define VAR2(type, param, valx, valy) \
    argi+=2; INIT var(e->k, argi-2, valx), var(e->k, argi-1, valy); \
    const type param = (type) { e->k->tdata[argi-2], e->k->tdata[argi-1] };

// set const variable value during initialisation
static inline void var(const XFadeEasingContext *k, int argi, double value)
{
    ((double*)k->tdata)[argi] = value; // cast away const on mutable when initialising to keep const when not
}

// set parameter arg or default value during initialisation
static av_noinline void arg(
        const XFadeEasingContext *k,
        int argi,
        const char *type,
        const char *param,
        double value) // default
{
    const XTransitionArgs *a = &k->targs;
    for (int j = 0; j < a->argc; j++)
        if (a->argv[j].param && !av_strcasecmp(a->argv[j].param, param))
            { value = a->argv[j].value; goto ret; } // named param
    if (a->argc > argi && !a->argv[argi].param && !isnan(a->argv[argi].value))
        value = a->argv[argi].value; // positional param
    ret:
    var(k, argi, value); // double to store 32-bit (10-digit) precision lossless colour values
    xe_debug(NULL, "param: %s %s = %g == %d(int) == 0x%08X(unsigned)\n", type, param, value, (int)value, (unsigned)value);
}

// extended transitions --------------------------------------------------

// GL transition names, algorithms, variable names & credits are replicated from the distribution source

static vec4 gl_angular(const XTransition *e) // by Fernando Kuteken
{ // License: MIT
    INIT_BEGIN
    ARG1(float, startingAngle, 90)
    ARG1(bool, clockwise, 0)
    VAR1(float, offset, radians(startingAngle))
    INIT_END
    float angle = atn2(sub2f(e->p, P5f)) + offset;
    float normalizedAngle = angle * M_1_2PIf + P5f;
    if (clockwise)
        normalizedAngle = -normalizedAngle;
    normalizedAngle = fract(normalizedAngle);
    return step(normalizedAngle, e->progress) ? e->b : e->a;
}

static vec4 gl_Bars(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(bool, vertical, 0)
    INIT_END
    float r = frandf(vertical ? e->p.x : e->p.y, 0);
    return (r > e->progress) ? e->a : e->b;
}

static vec4 gl_blend(const XTransition *e) // by scriptituk
{ // License: MIT
    INIT_BEGIN
    ARG1(int, mode, 0)
    INIT_END
    vec4 blended = blend(e, e->a, e->b, mode);
    return (e->progress < P5f)
        ? mix4(e->a, blended, e->progress * 2)
        : mix4(blended, e->b, e->progress * 2 - 1);
}

static vec4 gl_BookFlip(const XTransition *e) // by hong
{ // License: MIT
    INIT_END
    vec4 colour;
    float p = P5f - e->progress;
    vec2 c = sub2f(e->p, P5f);
    bool pr = step(p, c.x);
    if (c.x < 0) {
        if (!pr)
            return e->a;
        vec2 skewLeft = {
            (1 - c.x / p) * P5f,
            (c.y / (P5f - (p + p + 1) * c.x) + 1) * P5f
        };
        colour = getToColor(skewLeft);
    } else {
        if (pr)
            return e->b;
        vec2 skewRight = {
            (1 + c.x / p) * P5f,
            (c.y / (P5f - (p + p - 1) * c.x) + 1) * P5f
        };
        colour = getFromColor(skewRight);
    }
    float shadeVal = fmaxf(0.7f, fabsf(p) * 2);
    colour.p0 *= shadeVal;
    if (e->k->is_rgb)
        colour.p1 *= shadeVal, colour.p2 *= shadeVal;
    return colour;
}

static vec4 gl_Bounce(const XTransition *e) // by Adrian Purser
{ // License: MIT
    INIT_BEGIN
    ARG1(float, shadowAlpha, 0.6)
    ARG1(float, shadowHeight, 0.075)
    ARG1(float, bounces, 3)
    ARG1(int, direction, 0) // S,W,N,E
    ARG4(vec4, shadowColor, 0)
    INIT_END
    float phase = e->progress * M_PIf * bounces;
    float p = fabsf(cosf(phase)) * (1 - sinf(e->progress * M_PI_2f));
    if (direction & 2)
        p = 1 - p;
    vec2 v = e->p;
    float d = ((direction & 1) ? v.x : v.y) - p;
    if (step(d, 0)) {
        if (direction & 1)
            v.x = 1 + d;
        else
            v.y = 1 + d;
        return getFromColor(v);
    }
    if (!step(d, shadowHeight))
        return e->b;
    float m = mixf(
        d / shadowHeight * shadowAlpha + (1 - shadowAlpha),
        1,
        smoothstep(0.95f, 1, e->progress) // fade-out the shadow at the end
    );
    return mix4(e->b, shadowColor, 1 - m);
}

static vec4 gl_BowTie(const XTransition *e) // by huynx
{ // License: MIT
    INIT_BEGIN
    ARG1(bool, vertical, 0)
    INIT_END
    vec2 p = e->p, a = vec2f(P5f), b = a, c = a;
    if (vertical)
        a.y = e->progress, b.x -= e->progress, c.x += e->progress, b.y = c.y = 0;
    else
        a.x = e->progress, b.y -= e->progress, c.y += e->progress, b.x = c.x = 0;
    bool pass = 0;
    do {
        bool b1 = dot2(VEC2(p.x - a.x, p.y - a.y), VEC2(c.y - a.y, a.x - c.x)) < 0,
             b2 = dot2(VEC2(p.x - b.x, p.y - b.y), VEC2(a.y - b.y, b.x - a.x)) < 0,
             b3 = dot2(VEC2(p.x - c.x, p.y - c.y), VEC2(b.y - c.y, c.x - b.x)) < 0;
        if (b1 == b2 && b2 == b3) { // in triangle
            if (e->progress < 0.1f)
                break;
            if (!pass != (vertical ? p.y : p.x) < P5f)
                return pass ? e->a : e->b;
            // blur edge
            vec2 lineDir = sub2(b, a);
            vec2 perpDir = VEC2(lineDir.y, -lineDir.x);
            vec2 dirToPt = sub2(b, p);
            float dist1 = fabsf(dot2(normalize2(perpDir), dirToPt));
            lineDir = sub2(c, a);
            perpDir = VEC2(lineDir.y, -lineDir.x);
            dirToPt = sub2(c, p);
            float dist2 = fabsf(dot2(normalize2(perpDir), dirToPt));
            float min_dist = fminf(dist1, dist2);
            float m = (min_dist < 0.005f) ? min_dist * 200 : 1;
            return mix4(e->a, e->b, m);
        }
        if (vertical)
            a.y = 1 - a.y, b.y = c.y = 1;
        else
            a.x = 1 - a.x, b.x = c.x = 1;
    } while ((pass = !pass));
    return e->a;
}

static vec4 gl_ButterflyWaveScrawler(const XTransition *e) // by mandubian
{ // License: MIT
    INIT_BEGIN
    ARG1(float, amplitude, 1)
    ARG1(float, waves, 30)
    ARG1(float, colorSeparation, 0.3)
    INIT_END
    // func compute
    vec2 o = sub2f(mul2f(e->p, sinf(e->progress * amplitude)), P5f);
    vec2 h = { 1, 0 }; // horizontal vector
    float theta = acosf(dot2(o, h)) * waves; // butterfly polar function
    float disp = (expf(cosf(theta)) - cosf(theta * 4) * 2 + powf(sinf((theta * 2 - M_PIf) / 24), 5)) * 0.1f;
    // end compute
    float dp = disp * e->progress;
    vec4 texTo = getToColor(add2f(e->p, disp - dp)); // inv
    vec4 texFrom = getFromColor(add2f(e->p, dp));
    texFrom.p1 = getFromColor(add2f(e->p, dp * (1 + colorSeparation))).p1;
    texFrom.p2 = getFromColor(add2f(e->p, dp * (1 - colorSeparation))).p2;
//  if (!e->k->is_rgb)
//      return gbr2yuv(mix4(yuv2gbr(texFrom), yuv2gbr(texTo), e->progress));
// TODO: conversions don't make any difference; should we do RGB only?
    return mix4(texFrom, texTo, e->progress);
}

static vec4 gl_cannabisleaf(const XTransition *e) // by Flexi23
{ // License: MIT
    INIT_END
    if (e->progress == 0)
        return e->a;
    vec2 leaf_uv = div2f(sub2f(e->p, P5f), 10 * powf(e->progress, 3.5f));
    leaf_uv.y += 0.35f; // leaf offset
    float r = 0.18f; // leaf size
    float o = atn2(leaf_uv);
    // for curve see https://www.wolframalpha.com/input/?i=cannabis+curve
    float curve = (1 + sinf(o)) * (1 + 0.9f * cosf(8 * o)) * (1 + 0.1f * cosf(24 * o)) * (0.9f + 0.05f * cosf(200 * o));
    return step(r * curve, length2(leaf_uv)) ? e->a : e->b;
}

static vec4 gl_chessboard(const XTransition *e) // by lql
{ // License: MIT
    INIT_BEGIN
    ARG1(int, grid, 8)
    INIT_END
    vec2 st = mul2f(e->p, grid);
    vec2 idx = floor2(st);
    float g = st.x - idx.x;
    int checker = (int) (idx.x + idx.y) % 2;
    bool mixFactor = (e->progress < P5f)
        ? checker && step(g, e->progress * 2)
        : checker || step(g, e->progress * 2 - 1);
    return mixFactor ? e->b : e->a;
}

static vec4 gl_CornerVanish(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_END
    float b1 = (1 - e->progress) / 2, b2 = 1 - b1;
    return (betweenf(e->p.x, b1, b2) || betweenf(e->p.y, b1, b2)) ? e->b : e->a;
}

static vec4 gl_CrazyParametricFun(const XTransition *e) // by mandubian
{ // License: MIT
    INIT_BEGIN
    ARG1(float, a, 4)
    ARG1(float, b, 1)
    ARG1(float, amplitude, 120)
    ARG1(float, smoothness, 0.1)
    INIT_END
    vec2 p = mul2f(cossin2(e->progress), a - b);
    vec2 o = mul2f(cossin2(e->progress * ((a / b) - 1)), b);
    p.x += o.x;
    p.y -= o.y;
    o = sub2f(e->p, P5f);
    p = mul2f(p, e->progress * length2(o) * amplitude);
    p = div2f(VEC2(sinf(p.x), sinf(p.y)), smoothness);
    o = mul2(o, p);
    vec4 f = getFromColor(add2(e->p, o));
    return mix4(f, e->b, smoothstep(0.2f, 1, e->progress));
}

static vec4 gl_crosshatch(const XTransition *e) // by pthrasher
{ // License: MIT
    INIT_BEGIN
    ARG2(vec2, center, 0.5, 0.5)
    ARG1(float, threshold, 3)
    ARG1(float, fadeEdge, 0.1)
    INIT_END
    float dist = distance2(center, e->p) / threshold;
    float r = e->progress - fminf(frandf(e->p.y, 0), frandf(0, e->p.x));
    r = mixf(step(dist, r), 1, smoothstep(1 - fadeEdge, 1, e->progress));
    return mix4(e->a, e->b, mixf(0, r, smoothstep(0, fadeEdge, e->progress)));
}

static vec4 gl_CrossOut(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float c = e->progress / 2;
    vec2 p = sub2f(e->p, P5f);
    float ds = p.x + p.y, dd = p.y - p.x;
    if (betweenf(ds, -c, c) || betweenf(dd, -c, c))
        return e->b;
    float cs = c + smoothness;
    if (!(betweenf(ds, -cs, cs) || betweenf(dd, -cs, cs)))
        return e->a;
    float d = fabsf((p.x >= 0 != p.y >= 0) ? ds : dd);
    return mix4(e->b, e->a, (d - c) / smoothness);
}

static vec4 gl_crosswarp(const XTransition *e) // by Eke Péter
{ // License: MIT
    INIT_END
    float x = smoothstep(0, 1, e->progress * 2 + e->p.x - 1);
    vec2 c = sub2f(e->p, P5f);
    vec4 a = getFromColor(add2f(mul2f(c, 1 - x), P5f));
    vec4 b = getToColor(add2f(mul2f(c, x), P5f));
    return mix4(a, b, x);
}

static vec4 gl_CrossZoom(const XTransition *e) // by rectalogic
{ // License: MIT
    INIT_BEGIN
    ARG1(float, strength, 0.4)
    ARG2(vec2, centerFrom, 0.25, 0.5)
    ARG2(vec2, centerTo, 0.75, 0.5)
    INIT_END
    // linear interpolate centerpoint travel
    vec2 center = { lerp(centerFrom.x, centerTo.x, e->progress),
                    lerp(centerFrom.y, centerTo.y, e->progress) };
    XFadeEasingContext x = { .eargs = { .e.mode = EASE_INOUT } };
    float dissolve = rp_exponential(&x, e->progress);
    // mirrored sinusoidal loop: 0->strength then strength->0
    float strength2 = strength * rp_sinusoidal(&x, e->progress * 2);
    vec4 color = vec3f(0);
    float total = 0;
    vec2 toCenter = sub2(center, e->p);
    // randomize the lookup values to hide the fixed number of samples
    float offset = frand2(e->p);
    for (int t = 0; t <= 40; t++) {
        float percent = (t + offset) * 0.025f;
        float weight = (percent - percent * percent) * 4;
        vec2 p = add2(e->p, mul2f(toCenter, percent * strength2));
        vec4 c = mix4(getFromColor(p), getToColor(p), dissolve);
        color = add3(color, mul3f(c, weight));
        total += weight;
    }
    color = div3f(color, total);
    color.p3 = mixf(e->a.p3, e->b.p3, dissolve);
    return color;
}

static vec4 gl_cube(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG1(float, persp, 0.7)
    ARG1(float, unzoom, 0.3)
    ARG1(float, reflection, 0.4)
    ARG1(float, floating, 3)
    ARG4(vec4, background, 0)
    INIT_END
    float uz = unzoom * (P5f - fabsf(P5f - e->progress)) * 2;
    vec2 p = sub2f(mul2f(e->p, 1 + uz), uz / 2);
    float persp2 = e->progress * (1 - persp);
    vec2 fromP = {
        (p.x - e->progress) / (1 - e->progress),
        (p.y - persp2 * fromP.x / 2) / (1 - persp2 * fromP.x)
    };
    if (betweenUI2(fromP))
        return getFromColor(fromP);
    persp2 = 1 - mixf(e->progress * e->progress, 1, persp);
    vec2 toP = {
        p.x / e->progress,
        (p.y - persp2 * (1 - toP.x) / 2) / (1 - persp2 * (1 - toP.x))
    };
    if (betweenUI2(toP))
        return getToColor(toP);
    vec4 c = background;
    fromP.y = fromP.y * -1.2f - floating * 0.01f;
    if (betweenUI2(fromP))
        c = mix4(background, getFromColor(fromP), reflection * (1 - fromP.y));
    toP.y = toP.y * -1.2f - floating * 0.01f;
    if (betweenUI2(toP))
        c = mix4(background, getToColor(toP), reflection * (1 - toP.y));
    return c;
}

static vec4 gl_Diamond(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float d = asum2(sub2f(e->p, P5f));
    if (d < e->progress)
        return e->b;
    return (d > e->progress + smoothness)
        ? e->a : mix4(e->b, e->a, (d - e->progress) / smoothness);
}

static vec4 gl_DirectionalScaled(const XTransition *e) // by Thibaut Foussard
{ // License: MIT
    INIT_BEGIN
    ARG2(vec2, direction, 0, 1)
    ARG1(float, scale, 0.7)
    ARG4(vec4, background, 0)
    INIT_END
    float easedProgress = powf(sinf(e->progress * M_PI_2f), 3);
    vec2 p = add2(e->p, mul2f(sign2(direction), easedProgress));
    float s = 1 - (1 - 1 / scale) * sinf(e->progress * M_PIf);
    vec2 f = add2f(mul2f(sub2f(fract2(p), P5f), s), P5f);
    if (betweenUI2(f))
        return betweenUI2(p) ? getFromColor(f) : getToColor(f);
    return background;
}

static vec4 gl_directionalwarp(const XTransition *e) // by pschroen
{ // License: MIT
    INIT_BEGIN
    ARG1(float, smoothness, 0.1)
    ARG2(vec2, direction, -1, 1)
    INIT_END
    vec2 v = normalize2(direction);
    v = div2f(v, asum2(v));
    float d = (v.x + v.y) / 2;
    float m = dot2(e->p, v) - (d - P5f + e->progress * (1 + smoothness));
    m = 1 - smoothstep(-smoothness, 0, m);
    v = sub2f(e->p, P5f);
    vec4 a = getFromColor(add2f(mul2f(v, 1 - m), P5f));
    vec4 b = getToColor(add2f(mul2f(v, m), P5f));
    return mix4(a, b, m);
}

static vec4 gl_doorway(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG1(float, reflection, 0.4)
    ARG1(float, perspective, 0.4)
    ARG1(float, depth, 3)
    ARG4(vec4, background, 0)
    INIT_END
    float middleSlit = fabsf(e->p.x - P5f) * 2 - e->progress;
    if (middleSlit > 0) {
        float d = 1 / (1 + perspective * e->progress * (1 - middleSlit));
        vec2 pfr = {
            e->p.x + (e->p.x > P5f ? -P5f : P5f) * e->progress,
            (e->p.y + (1 - d) / 2) * d
        };
        if (betweenUI2(pfr))
            return getFromColor(pfr);
    }
    float size = mixf(1, depth, 1 - e->progress);
    vec2 pto = { (e->p.x - P5f) * size + P5f, (e->p.y - P5f) * size + P5f };
    if (betweenUI2(pto))
        return getToColor(pto);
    vec4 c = background;
    pto.y = pto.y * -1.2f - 0.02f;
    if (betweenUI2(pto))
        c = mix4(c, getToColor(pto), reflection * (1 - pto.y));
    return c;
}

static vec4 gl_DoubleDiamond(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float b1 = (1 - e->progress) / 2, b2 = 1 - b1;
    float d = asum2(sub2f(e->p, P5f));
    if (betweenf(d, b1, b2)) {
        if (betweenf(d, b1 + smoothness, b2 - smoothness))
            return e->b;
        return mix4(e->a, e->b, fminf(d - b1, b2 - d) / smoothness);
    }
    return e->a;
}

static vec4 gl_Dreamy(const XTransition *e) // by mikolalysenko
{ // License: MIT
    INIT_END
    float shifty = 0.03f * e->progress * cosf(10 * (e->progress + e->p.x));
    vec4 a = getFromColor(e->p.x, e->p.y + shifty);
    shifty = 0.03f * (1 - e->progress) * cosf(10 * ((1 - e->progress) + e->p.x));
    vec4 b = getToColor(e->p.x, e->p.y + shifty);
    return mix4(a, b, e->progress);
}

static vec4 gl_EdgeTransition(const XTransition *e) // by Woohyun Kim
{ // License: MIT
    INIT_BEGIN
    ARG1(float, edgeThickness, 0.001)
    ARG1(float, edgeBrightness, 8)
    INIT_END
    vec4 a[2]; // adjacent mix colours
    for (int k = 0; k < 2; k++) {
        vec4 c[9]; // adjacent pixel array for c[4]: 0 3 6
        for (int i = 0; i < 9; i++) {             // 1 4 7
            ivec2 j = { i / 3, i % 3 };           // 2 5 8
            vec2 p = add2(e->p, mul2f(VEC2(j.x - 1, j.y - 1), edgeThickness));
            c[i] = k ? getToColor(p) : getFromColor(p);
        }
        vec4 dx = add3(abs3(mul3f(sub3(c[7], c[1]), 2)), add3(abs3(sub3(c[2], c[6])), abs3(sub3(c[8], c[0]))));
        vec4 dy = add3(abs3(mul3f(sub3(c[3], c[5]), 2)), add3(abs3(sub3(c[6], c[8])), abs3(sub3(c[0], c[2]))));
        float delta = length3(mul3f(add3(dx, dy), 0.25f * P5f));
        a[k] = mul3f(c[4], clipUI(edgeBrightness * delta));
        a[k].p3 = k ? e->b.p3 : e->a.p3;
    }
    vec4 start = mix4(e->a, a[0], clipUI(e->progress * 2));
    vec4 end = mix4(a[1], e->b, clipUI(e->progress * 2 - 1));
    return mix4(start, end, e->progress);
}

static vec4 gl_Exponential_Swish(const XTransition *e) // by Boundless
{ // License: MIT
    INIT_BEGIN
    ARG1(float, zoom, 0.8)
    ARG1(float, angle, 0)
    ARG2(vec2, offset, 0, 0)
    ARG1(int, exponent, 4)
    ARG2(ivec2, wrap, 2, 2)
    ARG1(float, blur, 0) // changed from 0.5 which makes it extremely slow
    ARG4(vec4, background, 0)
    VAR1(float, frames, e->k->duration * e->k->framerate)
    VAR1(float, deg, radians(angle))
    VAR1(float, ratio2, (e->ratio - 1) / 2)
    INIT_END
    const int iters = 50; // TODO: experiment with this
    const vec2 uv = sub2f(e->p, P5f);
    vec4 comp = vec4f(0);
    for (int i = 0; i < iters; i++) {
        float p = clipUI(e->progress + (float)i * blur / frames / iters);
        float pa0 = powf(p + p, exponent), pa1 = powf((1 - p) * 2, exponent),
              px0 = 1 - pa0 * fabsf(zoom), px1 = 1 - pa1 * fabsf(zoom),
              px2 = 1 - pa0 * fmaxf(-zoom, 0), px3 = 1 - pa1 * fmaxf(zoom, 0);
        vec2 uv0, uv1;
        if (zoom > 0)
            uv0 = mul2f(uv, px0), uv1 = div2f(uv, px1);
        else if (zoom < 0)
            uv0 = div2f(uv, px0), uv1 = mul2f(uv, px1);
        else
            uv0 = uv1 = uv;
        uv0 = sub2(add2f(uv0, P5f), mul2f(offset, pa0 / px2));
        uv0.x = uv0.x * e->ratio - ratio2;
        uv0 = add2f(rot2(sub2f(uv0, P5f), -deg * pa0), P5f);
        uv0.x = (uv0.x + ratio2) / e->ratio;
        uv1 = add2(add2f(uv1, P5f), mul2f(offset, pa1 / px3));
        uv1.x = uv1.x * e->ratio - ratio2;
        uv1 = add2f(rot2(sub2f(uv1, P5f), deg * pa1), P5f);
        uv1.x = (uv1.x + ratio2) / e->ratio;
        if (wrap.x == 2)
            uv0.x = acosf(cosf(M_PIf * uv0.x)) * M_1_PIf, uv1.x = acosf(cosf(M_PIf * uv1.x)) * M_1_PIf;
        else if (wrap.x == 1)
            uv0.x = fract(uv0.x), uv1.x = fract(uv1.x);
        if (wrap.y == 2)
            uv0.y = acosf(cosf(M_PIf * uv0.y)) * M_1_PIf, uv1.y = acosf(cosf(M_PIf * uv1.y)) * M_1_PIf;
        else if (wrap.y == 1)
            uv0.y = fract(uv0.y), uv1.y = fract(uv1.y);
        bool b = (p < P5f);
        vec4 c = (!wrap.x && ((b && !betweenUI(uv0.x)) || (!b && !betweenUI(uv1.x)))) ||
                 (!wrap.y && ((b && !betweenUI(uv0.y)) || (!b && !betweenUI(uv1.y))))
                 ? background : b ? getFromColor(uv0) : getToColor(uv1);
        if (blur == 0)
            return c;
        comp.p0 += c.p0 / iters;
        if (e->k->is_rgb)
            comp.p1 += c.p1 / iters, comp.p2 += c.p2 / iters;
        else
            comp.p1 = c.p1, comp.p2 = c.p2;
        comp.p3 = c.p3;
    }
    return comp;
}

static vec4 gl_FanIn(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float theta = M_PIf * e->progress;
    float d = atan2f(fabsf(e->p.x - P5f), (e->p.y < P5f) ? 0.25f - e->p.y : e->p.y - 0.75f) - theta;
    if (d < 0)
        return e->b;
    return (d < smoothness) ? mix4(e->b, e->a, d / smoothness) : e->a;
}

static vec4 gl_FanOut(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float theta = M_2PIf * e->progress;
    float d = M_PIf + atan2f(P5f - e->p.y, (e->p.x < P5f) ? 0.25f - e->p.x : e->p.x - 0.75f) - theta;
    if (d < 0)
        return e->b;
    return (d < smoothness) ? mix4(e->b, e->a, d / smoothness) : e->a;
}

static vec4 gl_FanUp(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    INIT_END
    float theta = M_PI_2f * e->progress;
    float d = atan2f(fabsf(e->p.x - P5f), 1 - e->p.y) - theta;
    if (d < 0)
        return e->b;
    return (d < smoothness) ? mix4(e->b, e->a, d / smoothness) : e->a;
}

static vec4 gl_Flower(const XTransition *e) // by Mark Craig
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(float, smoothness, 0.05)
    ARG1(float, rotation, 360)
    float h, r;
    vec2 v;
    INIT {
        r = radians(162);
        v = cossin2(r), v.y--;
        h = dot2(v, v);
        r = radians(234);
        v = cossin2(r), v.y--;
        h -= dot2(v, v) / 4;
    }
    VAR1(float, ang, radians(36))
    VAR1(float, fang, (1 - sqrtf(h)) / cosf(ang))
    INIT_END
    v = VEC2((e->p.x - P5f) * e->ratio, P5f - e->p.y);
    float theta = radians(e->progress * rotation);
    float theta1 = atan2f(v.x, v.y) + theta;
    float theta2 = glmod(fabsf(theta1), ang);
    float ro = e->ratio / 0.731f * e->progress;
    float ri = ro * fang;
    if (glmod(truncf(theta1 / ang), 2) == 0)
        r = theta2 / ang * (ro - ri) + ri;
    else
        r = (1 - theta2 / ang) * (ro - ri) + ri;
    float r2 = length2(v);
    if (r2 > r + smoothness)
        return e->a;
    if (r2 > r)
        return mix4(e->b, e->a, (r2 - r) / smoothness);
    return e->b;
}

static vec4 gl_GridFlip(const XTransition *e) // by TimDonselaar
{ // License: MIT
    INIT_BEGIN
    ARG2(ivec2, size, 4, 4)
    ARG1(float, pause, 0.1)
    ARG1(float, dividerWidth, 0.05)
    ARG1(float, randomness, 0.1)
    ARG4(vec4, background, 0)
    INIT_END
    const vec2 rectangleSize = rcp2(vec2i(size));
    const vec2 rectanglePos = floor2(mul2(vec2i(size), e->p));
    float top = rectangleSize.y * (rectanglePos.y + 1),
          bottom = rectangleSize.y * rectanglePos.y,
          minY = fminf(fabsf(e->p.y - top), fabsf(e->p.y - bottom)),
          left = rectangleSize.x * rectanglePos.x,
          right = rectangleSize.x * (rectanglePos.x + 1),
          minX = fminf(fabsf(e->p.x - left), fabsf(e->p.x - right));
    float dividerSize = fminf(rectangleSize.x, rectangleSize.y) * dividerWidth;
    bool individer = fminf(minX, minY) < dividerSize;
    if (e->progress < pause)
        return mix4(background, e->a, individer ? 1 - e->progress / pause : 1);
    if (1 - e->progress < pause)
        return mix4(background, e->b, individer ? 1 - (1 - e->progress) / pause : 1);
    if (individer)
        return background;
    float r = frand2(rectanglePos) - randomness;
    float cp = smoothstep(0, 1 - r, (e->progress - pause) / (1 - pause * 2));
    float offset = rectangleSize.x / 2 + left;
    vec2 p = { (e->p.x - offset) / fabsf(cp - P5f) / 2 + offset, e->p.y };
    float s = step(fabsf(size.x * (e->p.x - left) - P5f), fabsf(cp - P5f));
    return mix4(background, mix4(getToColor(p), getFromColor(p), step(cp, P5f)), s);
}

static vec4 gl_heart(const XTransition *e) // by gre
{ // License: MIT
    INIT_END
    if (e->progress == 0)
        return e->a;
    vec2 o = div2f(sub2(e->p, VEC2(P5f, 0.4f)), 1.6f * e->progress);
    float a = o.x * o.x + o.y * o.y - 0.3f;
    return step(a * a * a, o.x * o.x * o.y * o.y * o.y) ? e->b : e->a;
}

static vec4 gl_hexagonalize(const XTransition *e) // by Fernando Kuteken
{ // License: MIT
    INIT_BEGIN
    ARG1(int, steps, 50)
    ARG1(float, horizontalHexagons, 20)
    INIT_END
    float dist = fminf(e->progress, 1 - e->progress) * 2;
    if (steps > 0)
        dist = ceilf(dist * steps) / steps;
    if (dist > 0) {
        typedef struct { float q, r, s; } Hexagon;
        float sqrt3 = sqrtf(3), size = sqrt3 / 3 * dist / horizontalHexagons;
        // hexagonFromPoint
        vec2 point = { (e->p.x - P5f) / size, (e->p.y / e->ratio - P5f) / size };
        Hexagon hex = { .q = (sqrt3 * point.x - point.y) / 3, .r = 2.f / 3.f * point.y };
        hex.s = -hex.q - hex.r;
        // roundHexagon
        Hexagon f = { floorf(hex.q + P5f), floorf(hex.r + P5f), floorf(hex.s + P5f) };
        float deltaQ = fabsf(f.q - hex.q), deltaR = fabsf(f.r - hex.r), deltaS = fabsf(f.s - hex.s);
        if (deltaQ > deltaR && deltaQ > deltaS)
            f.q = -f.r - f.s;
        else if (deltaR > deltaS)
            f.r = -f.q - f.s;
        // pointFromHexagon
        point = VEC2(
            (sqrt3 * f.q + sqrt3 / 2 * f.r) * size + P5f,
            (3.f / 2.f * f.r * size + P5f) * e->ratio
        );
        return mix4(getFromColor(point), getToColor(point), e->progress);
    }
    return mix4(e->a, e->b, e->progress);
}

static vec4 inverted_page_curl(const XTransition *e, int angle, float radius, bool reverseEffect);
static vec4 gl_InvertedPageCurl(const XTransition *e) // by Hewlett-Packard
{ // License: BSD 3-Clause
    INIT_BEGIN
    ARG1(int, angle, 100)
    ARG1(float, radius, M_1_2PIf)
    ARG1(bool, reverseEffect, 0)
    float a;
    INIT {
        a = angle;
        if (a != 30 && a != 100)
            xe_error(NULL, "invalid gl_InvertedPageCurl angle %g, use 100 (default) or 30\n", a), a = 100;
    }
    VAR1(float, ang, a)
    INIT_END
    return inverted_page_curl(e, ang, radius, reverseEffect); // licensed code
}

static vec4 gl_kaleidoscope(const XTransition *e) // by nwoeanhinnogaehr
{ // License: MIT
    INIT_BEGIN
    ARG1(float, speed, 1)
    ARG1(float, angle, 1)
    ARG1(float, power, 1.5)
    INIT_END
    float t = powf(e->progress, power) * speed;
    vec2 p = sub2f(e->p, P5f);
    for (int i = 0; i < 7; i++) {
        p = abs2(sub2f(mod2(rot2(p, M_PI_2f - t), 2), 1));
        t += angle;
    }
    vec4 m = mix4(e->a, e->b, e->progress);
    vec4 n = mix4(getFromColor(p), getToColor(p), e->progress);
    return mix4(m, n, 1 - fabsf(e->progress - P5f) * 2);
}

static vec4 gl_Lissajous_Tiles(const XTransition *e) // by Boundless
{ // License: MIT
    INIT_BEGIN
    ARG2(ivec2, grid, 10, 10)
    ARG1(float, speed, 0.5)
    ARG2(vec2, freq, 2, 3)
    ARG1(float, offset, 2)
    ARG1(float, zoom, 0.8)
    ARG1(float, fade, 3)
    ARG4(vec4, background, 0)
    VAR1(int, n, grid.x * grid.y)
    VAR2(vec2, r, 1.f / grid.x, 1.f / grid.y)
    VAR2(vec2, f, freq.x * M_2PIf, freq.y * M_2PIf)
    VAR1(float, z, zoom / 2)
    INIT_END
    vec4 c = background;
    float k = 1. - powf(fabsf(1 - e->progress * 2), 3); // transition curve
    float l = e->progress * e->progress * (fade + 1) * 2 - fade;
    vec2 i = { e->progress * speed * 6, offset + 1 };
    i.y *= i.x;
    for (int h = 0; h < n; h++) {
        vec2 g = { h % grid.x, h / grid.x }; // integer division
        vec2 t = mul2(g, r); // tile
        float a = t.x * r.y + t.y;
        vec2 p = add2(mul2f(f, a), i);
        p = VEC2(cosf(p.x), sinf(p.y));
        p = sub2f(add2(add2(add2(e->p, t), mul2f(r, P5f)), mul2f(p, z)), P5f);
        p = add2(mul2f(p, k), mul2f(e->p, (1 - k)));
        if (betweenf(p.x, t.x, t.x + r.x) && betweenf(p.y, t.y, t.y + r.y)) { // mask for each tile
            float m = clipUI(a * fade + l);
            c = mix4(getFromColor(p), getToColor(p), m);
        }
    }
    return c;
}

static vec4 gl_morph(const XTransition *e) // by paniq
{ // License: MIT
    INIT_BEGIN
    ARG1(float, strength, 0.1)
    INIT_END
    vec2 oa = sub2f(add2f(VEC2(e->a.p2, e->a.p0), e->a.p1), 1);
    vec2 ob = sub2f(add2f(VEC2(e->b.p2, e->b.p0), e->b.p1), 1);
    vec2 oc = mul2f(add2(oa, ob), P5f);
    vec2 pf = add2(e->p, mul2f(oc, strength * e->progress));
    vec2 pt = sub2(e->p, mul2f(oc, strength * (1 - e->progress)));
    return mix4(getFromColor(pf), getToColor(pt), e->progress);
}

static vec4 gl_Mosaic(const XTransition *e) // by Xaychru
{ // License: MIT
    INIT_BEGIN
    ARG1(int, endx, 2)
    ARG1(int, endy, -1)
    INIT_END
    float rpr = e->progress * 2 - 1;
    float az = fabsf(3 - rpr * rpr * 2);
    float ci = P5f - cosf(e->progress * M_PIf) / 2; // CosInterpolation
    vec2 ps = {
        (e->p.x - P5f) * az + mixf(P5f, endx + P5f, ci * ci),
        (e->p.y - P5f) * az + mixf(P5f, endy + P5f, ci * ci)
    };
    vec2 crp = floor2(ps); // floor(crp)
    vec2 mrp = sub2(ps, crp); // == glmod(ps, 1) == fract(ps)
    float r = frand2(crp);
    bool onEnd = crp.x == endx && crp.y == endy;
    if(!onEnd) {
        float ang = truncf(r * 4) * M_PI_2f;
        mrp = add2f(rot2(sub2f(mrp, P5f), ang), P5f);
    }
    return (onEnd || r > P5f) ? getToColor(mrp) : getFromColor(mrp);
}

static vec4 gl_perlin(const XTransition *e) // by Rich Harris
{ // License: MIT
    INIT_BEGIN
    ARG1(float, scale, 4)
    ARG1(float, smoothness, 0.01)
    INIT_END
    vec2 s = mul2f(e->p, scale), i = floor2(s), f = sub2(s, i); // fract
    vec2 u = { smoothstep(0, 1, f.x), smoothstep(0, 1, f.y) };
    float a = frandf(i.x, i.y), b = frandf(i.x + 1, i.y), c = frandf(i.x, i.y + 1), d = frandf(i.x + 1, i.y + 1);
    float n = mixf(a, b, u.x) + ((c - a) * (1 - u.x) + (d - b) * u.x) * u.y;
    float p = mixf(-smoothness, 1 + smoothness, e->progress);
    float q = smoothstep(p - smoothness, p + smoothness, n);
    return mix4(e->a, e->b, 1 - q);
}

static vec4 gl_pinwheel(const XTransition *e) // by Mr Speaker
{ // License: MIT
    INIT_BEGIN
    ARG1(float, speed, 1)
    INIT_END
    float circPos = atn2(sub2f(e->p, P5f)) + e->progress * speed;
    float modPos = glmod(circPos, M_PI_4f);
    return (e->progress <= modPos) ? e->a : e->b;
}

static vec4 gl_polar_function(const XTransition *e) // by Fernando Kuteken
{ // License: MIT
    INIT_BEGIN
    ARG1(int, segments, 5)
    INIT_END
    float angle = atn2(sub2f(e->p, P5f)) - M_PI_2f;
    float radius = cosf(segments * angle) / 4 + 1;
    float difference = length2(sub2f(e->p, P5f));
    return (difference > radius * e->progress) ? e->a : e->b;
}

static vec4 gl_PolkaDotsCurtain(const XTransition *e) // by bobylito
{ // License: MIT
    INIT_BEGIN
    ARG1(float, dots, 20)
    ARG2(vec2, center, 0, 0)
    INIT_END
    vec2 p = fract2(mul2f(e->p, dots));
    return (distance2(p, vec2f(P5f)) < e->progress / distance2(e->p, center)) ? e->b : e->a;
}

static vec4 gl_powerKaleido(const XTransition *e) // by Boundless
{ // License: MIT
    INIT_BEGIN
    ARG1(float, scale, 2)
    ARG1(float, z, 1.5)
    ARG1(float, speed, 5)
    VAR1(float, rad, radians(120)) // change this value to get different mirror effects
    VAR1(float, dist, scale / 10)
    INIT_END
    vec2 uv = mul2f(sub2f(e->p, P5f), e->ratio * z);
    float a = e->progress * speed;
    uv = rot2(uv, a);
    for (int iter = 0; iter < 10; iter++) {
        for (float i = 0; i < M_2PIf; i += rad) {
            vec2 v = cossin2(i);
            bool b = asinf(v.x) > 0; // == glmod(i + M_PI_2f, M_2PIf) < M_PIf
            bool d = uv.y - v.x * dist > v.y / v.x * (uv.x + v.y * dist);
            if (b == d) {
                vec2 p = { uv.x + v.y * dist * 2, uv.y - v.x * dist * 2 };
                uv = sub2(mul2f(v, dot2(p, v) * 2), p);
            }
        }
    }
    uv = rot2(uv, -a);
    uv.x /= e->ratio;
    uv = div2f(add2f(uv, P5f), 2);
    uv = mul2f(abs2(sub2(uv, floor2(add2f(uv, P5f)))), 2);
    float m = (cosf(e->progress * M_2PIf) + 1) * P5f;
    vec2 uvMix = mix2(uv, e->p, m);
    m = (cosf((e->progress - 1) * M_PIf) + 1) * P5f;
    return mix4(getFromColor(uvMix), getToColor(uvMix), m);
}

static vec4 gl_randomNoisex(const XTransition *e) // by towrabbit
{ // License: MIT
    INIT_END
    float uvz = floorf(frand2(e->p) + e->progress);
    return mix4(e->a, e->b, uvz);
}

static vec4 gl_randomsquares(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG2(ivec2, size, 10, 10)
    ARG1(float, smoothness, 0.5)
    INIT_END
    float r = frand2(floor2(mul2(vec2i(size), e->p)));
    float m = smoothstep(0, -smoothness, r - e->progress * (1 + smoothness));
    return mix4(e->a, e->b, m);
}

static vec4 gl_ripple(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG1(float, amplitude, 100)
    ARG1(float, speed, 50)
    INIT_END
    vec2 dir = sub2f(e->p, P5f);
    float dist = length2(dir);
    float s = (sinf(e->progress * (dist * amplitude - speed)) + P5f) / 30;
    vec2 offset = add2(e->p, mul2f(dir, s));
    return mix4(getFromColor(offset), e->b, smoothstep(0.2f, 1, e->progress));
}

static vec4 gl_Rolls(const XTransition *e) // by Mark Craig
{ // License: MIT
    INIT_BEGIN
    ARG1(int, type, 0)
    ARG1(bool, RotDown, 0)
    INIT_END
    float theta = M_PI_2f * e->progress;
    if (type >= 2 == !RotDown)
        theta = -theta;
    vec2 uvi = e->p;
    if (!(type == 1 || type == 2))
        uvi.x = 1 - uvi.x;
    if (type >= 2)
        uvi.y = 1 - uvi.y;
    uvi.x *= e->ratio;
    vec2 uv2 = rot2(uvi, theta);
    uv2.x /= e->ratio;
    if (betweenUI2(uv2)) {
        if (type != 1 && type != 2)
            uv2.x = 1 - uv2.x;
        if (type >= 2)
            uv2.y = 1 - uv2.y;
        return getFromColor(uv2);
    }
    return e->b;
}

static vec4 gl_RotateScaleVanish(const XTransition *e) // by Mark Craig
{ // License: MIT
    INIT_BEGIN
    ARG1(bool, fadeInSecond, 1)
    ARG1(bool, reverseEffect, 0)
    ARG1(bool, reverseRotation, 0)
    ARG4(vec4, background, 0)
    ARG1(bool, trkMat, 0)
    INIT_END
    float t = reverseEffect ? 1 - e->progress : e->progress;
    float theta = (reverseRotation ? -t : t) * M_2PIf;
    vec2 c2 = rot2(VEC2((e->p.x - P5f) * e->ratio, e->p.y - P5f), theta);
    float rad = fmaxf(0.00001f, 1 - t);
    vec2 uv2 = { c2.x / rad + e->ratio / 2, c2.y / rad + P5f };
    uv2.x /= e->ratio;
    vec4 col3, ColorTo = reverseEffect ? e->a : e->b;
    if (betweenUI2(uv2))
        col3 = reverseEffect ? getToColor(uv2) : getFromColor(uv2);
    else if (fadeInSecond)
        col3 = background;
    else
        col3 = ColorTo;
    if (trkMat)
        t = 1 - col3.p3;
    return mix4(col3, ColorTo, t);
}

static vec4 gl_rotateTransition(const XTransition *e) // by haiyoucuv
{ // License: MIT
    INIT_END
    vec2 p = add2f(rot2(sub2f(e->p, P5f), e->progress * M_2PIf), P5f);
    return mix4(getFromColor(p), getToColor(p), e->progress);
}

static vec4 gl_rotate_scale_fade(const XTransition *e) // by Fernando Kuteken
{ // License: MIT
    INIT_BEGIN
    ARG2(vec2, center, 0.5, 0.5)
    ARG1(float, rotations, 1)
    ARG1(float, scale, 8)
    ARG4(vec4, background, 0.15)
    INIT_END
    vec2 difference = sub2(e->p, center);
    float dist = length2(difference);
    vec2 dir = div2f(difference, dist);
    float angle = -M_2PIf * rotations * e->progress;
    vec2 rotatedDir = rot2(dir, angle);
    float currentScale = mixf(scale, 1, fabsf(e->progress - P5f) * 2);
    vec2 rotatedUv = add2(center, mul2f(rotatedDir, dist / currentScale));
    if (betweenUI2(rotatedUv))
        return mix4(getFromColor(rotatedUv), getToColor(rotatedUv), e->progress);
    return background;
}

static vec4 gl_SimpleBookCurl(const XTransition *e) // by scriptituk
{ // License: MIT
    INIT_BEGIN
    ARG1(int, angle, 150)
    ARG1(float, radius, 0.1)
    ARG1(float, shadow, 0.2)
    // setup
//static int dbg=0;
    float phi;
    vec2 i, dir;
    INIT {
        phi = radians(angle) - M_PI_2f; // target curl angle
        i = cossin2(phi);
        dir = normalize2(VEC2(i.x * e->ratio, i.y)); // direction unit vector
        i = VEC2((dir.x >= 0) ? P5f : -P5f, (dir.y >= 0) ? P5f : -P5f);
    }
    VAR2(vec2, q, i.x, i.y) // quadrant corner
    INIT i = abs2(dir);
    VAR1(float, k, (i.x == 0) ? M_PI_2f : atn2(i)) // absolute curl angle
    INIT i = mul2f(dir, dot2(q, dir)); // initial position, curl axis on corner
    VAR1(float, m1, length2(i)) // length for rotating
    VAR1(float, m2, M_PIf * radius) // length of half-cylinder arc
//INIT xe_debug(NULL, "gl_SimpleBookCurl phi=%g=%g dir=%g,%g q=%g,%g k=%g=%g i=%g,%g m1=%g m2=%g\n", phi, degrees(phi), dir.x, dir.y, q.x, q.y, k, degrees(k), i.x, i.y, m1, m2);
    INIT_END
    // get new angle & progress point
    float rad = radius; // working radius
    vec2 p; // working curl axis point
    float m = (m1 + m2) * e->progress; // current position along lengths
    if (m < m1) { // rotating page
        XFadeEasingContext x = { .eargs = { .e.mode = EASE_INOUT } };
        phi = k * (1 - rp_sinusoidal(&x, m / m1)); // eased new absolute curl angle
        dir = normalize2(mul2(cossin2(phi), q)); // new direction
        p = mul2f(dir, m1 - m);
/*      if (P5f - (m1 - m) * fabsf(dir.y) > FLT_EPSILON) { // curled beyond spine
            i = mul2f(dir, dot2(VEC2(0, q.y), dir)); // for curl axis on spine
            phi = M_PI_2f - phi;
            dir = normalize2(mul2(VEC2(P5f * tan(phi) + distance2(i, p) * cosf(phi), P5f), q));
            p = mul2f(dir, dot2(VEC2(0, q.y), dir)); // clamped curl axis to spine
if(!dbg)dbg=1,xe_debug(NULL, "gl_SimpleBookCurl_dbg phi=%g=%g dir=%g,%g p=%g,%g i=%g,%g m=%g\n", phi, degrees(phi), dir.x, dir.y, p.x, p.y, i.x, i.y, m);
        }*/ // TODO: finish this - prevent small radii crossing spine
    } else { // straightening curl
        XFadeEasingContext x = { .eargs = { .e.mode = EASE_OUT } };
        if (m2 > 0)
            rad *= 1 - rp_quadratic(&x, (m - m1) / m2); // eased new radius
        dir = VEC2(q.x + q.x, 0); // new direction
        p = VEC2(0, 0);
    }
    // get point relative to curl axis
    i = sub2f(e->p, P5f); // distance of current point from centre
    float dist = dot2(sub2(i, p), dir); // distance of point from curl axis
    p = sub2(i, mul2f(dir, dist)); // point perpendicular to curl axis
    // map point to curl
    vec4 c = e->b; // return colour
    bool s = false; // shadow flag
    if (dist < 0) { // point is over flat A
        c = e->a;
        p = add2f(mul2(add2(p, mul2f(dir, M_PIf * rad - dist)), VEC2(-1, 1)), P5f);
        if (betweenUI2(p)) // on flat back of A
            c = getToColor(p);
    } else if (rad > 0) { // curled A
        // map to cylinder point
        phi = asinf(dist / rad);
        vec2 p2 = add2f(mul2(add2(p, mul2f(dir, (M_PIf - phi) * rad)), VEC2(-1, 1)), P5f);
        vec2 p1 = add2f(add2(p, mul2f(dir, phi * rad)), P5f);
        if (betweenUI2(p2)) // on curling back of A
            c = getToColor(p2), s = true;
        else if (betweenUI2(p1)) // on curling front of A
            c = getFromColor(p1);
        else // on B
            s = true;
    }
    if (s) { // need shadow
        // TODO: ok over A, makes a tideline over B for large radius
//      d = (1. - distance2(p, q) * 1.414) * powf(?, shadow);
        float d = powf(clipUI(fabsf(dist - rad) / rad), shadow);
        c.p0 *= d;
        if (e->k->is_rgb)
            c.p1 *= d, c.p2 *= d;
    }
    return c;
}

// see https://www.shadertoy.com/view/ls3cDB
// and https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/
static vec4 gl_SimplePageCurl(const XTransition *e) // by Andrew Hung
{ // License: MIT (assumed)
    INIT_BEGIN
    ARG1(int, angle, 80)
    ARG1(float, radius, 0.15)
    ARG1(bool, roll, 0)
    ARG1(bool, reverseEffect, 0)
    ARG1(bool, greyBack, 0)
    ARG1(float, opacity, 0.8)
    ARG1(float, shadow, 0.2)
    // setup
    float phi;
    vec2 q, f;
    INIT {
        phi = radians(angle) - M_PI_2f; // target curl angle
        f = cossin2(phi);
        f = normalize2(VEC2(f.x * e->ratio, f.y));
        q = VEC2((f.x >= 0) ? P5f : -P5f, (f.y >= 0) ? P5f : -P5f); // quadrant corner
    }
    VAR2(vec2, dir, f.x, f.y) // direction unit vector
    INIT f = mul2f(dir, dot2(q, dir));
    VAR2(vec2, i, f.x, f.y) // initial position, curl axis on corner
    INIT {
        f = sub2(mul2f(dir, -2 * radius), i); // final position, curl & shadow just out of view
        f = sub2(f, i);
    }
    VAR2(vec2, m, f.x, f.y) // path extent, perpendicular to curl axis
    INIT_END
    // get point relative to curl axis
    vec2 p = add2(i, mul2f(m, (reverseEffect ? 1 - e->progress : e->progress))); // current position
    q = sub2f(e->p, P5f); // distance of current point from centre
    float dist = dot2(sub2(q, p), dir); // distance of point from curl axis
    p = sub2(q, mul2f(dir, dist)); // point perpendicular to curl axis
    // map point to curl
    vec4 c = reverseEffect ? e->a : e->b;
    bool g = false, o = false, s = false; // getcolor & opacity & shadow flags
    if (dist < 0) { // point is over flat or rolling A
        if (!roll) { // curl
            p = add2f(add2(p, mul2f(dir, M_PIf * radius - dist)), P5f);
            g = true;
        } else if (-dist < radius) { // possibly on roll over
            phi = asinf(-dist / radius);
            p = add2f(add2(p, mul2f(dir, (M_PIf + phi) * radius)), P5f);
            g = s = true;
        }
        if (g && betweenUI2(p)) // on back of A
            o = true;
        else
            c = reverseEffect ? e->b : e->a, g = false;
    } else if (radius > 0) { // point is over curling A or flat B
        // map to cylinder point
        phi = asinf(dist / radius);
        vec2 p2 = add2f(add2(p, mul2f(dir, (M_PIf - phi) * radius)), P5f);
        vec2 p1 = add2f(add2(p, mul2f(dir, phi * radius)), P5f);
        if (betweenUI2(p2)) // on curling back of A
            p = p2, g = o = s = true;
        else if (betweenUI2(p1)) // on curling front of A
            p = p1, g = true;
        else // on B
            s = true;
    }
    if (g) // on A
        c = reverseEffect ? getToColor(p) : getFromColor(p);
    if (o) { // need opacity
        if (greyBack) {
            if (e->k->is_rgb)
                c.p0 = c.p1 = c.p2 = (c.p0 + c.p1 + c.p2) / 3;
            else
                c.p1 = c.p2 = P5f;
        }
        c.p0 += opacity * (1 - c.p0);
        if (e->k->is_rgb)
            c.p1 += opacity * (1 - c.p1), c.p2 += opacity * (1 - c.p2);
    }
    if (s && radius > 0) { // need shadow
        // TODO: ok over A, makes a tideline over B for large radius
        float d = dist + (g ? radius : -radius);
        d = powf(clipUI(fabsf(d) / radius), shadow);
        c.p0 *= d;
        if (e->k->is_rgb)
            c.p1 *= d, c.p2 *= d;
    }
    return c;
}

static vec4 gl_Slides(const XTransition *e) // by Mark Craig
{ // License: MIT
    INIT_BEGIN
    ARG1(int, type, 0)
    ARG1(bool, slideIn, 0)
    INIT_END
    float rad = slideIn ? e->progress : 1 - e->progress, rrad = 1 - rad, rrad2 = rrad * P5f;
    float xc1, yc1;
    switch (type) {
        case 0:  xc1 = rrad2, yc1 = 0;     break; // up
        case 1:  xc1 = rrad,  yc1 = rrad2; break; // right
        case 2:  xc1 = rrad2, yc1 = rrad;  break; // down
        case 3:  xc1 = 0,     yc1 = rrad2; break; // left
        case 4:  xc1 = rrad,  yc1 = 0;     break; // t-r
        case 5:  xc1 =        yc1 = rrad;  break; // b-r
        case 6:  xc1 = 0,     yc1 = rrad;  break; // b-l
        case 7:  xc1 =        yc1 = 0;     break; // t-l
        default: xc1 =        yc1 = rrad2; break; // default centre
    }
    vec2 uv = { e->p.x, 1 - e->p.y };
    if (betweenf(uv.x, xc1, xc1 + rad) && betweenf(uv.y, yc1, yc1 + rad)) {
        vec2 uv2 = { (uv.x - xc1) / rad, 1 - (uv.y - yc1) / rad };
        return slideIn ? getToColor(uv2) : getFromColor(uv2);
    }
    return slideIn ? e->a : e->b;
}

static vec4 gl_squareswire(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG2(ivec2, squares, 10, 10)
    ARG2(vec2, direction, 1.0, -0.5)
    ARG1(float, smoothness, 1.6)
    vec2 u;
    INIT u = normalize2(direction), u = div2f(u, asum2(u));
    VAR2(vec2, v, u.x, u.y)
    VAR1(float, d, (v.x + v.y) / 2)
    INIT_END
    float m = dot2(e->p, v) - (d - P5f + e->progress * (1 + smoothness));
    float pr = smoothstep(-smoothness, 0, m);
    vec2 squarep = fract2(mul2(e->p, vec2i(squares)));
    return between2(squarep, pr / 2, 1 - pr / 2) ? e->b : e->a;
}

static vec4 gl_StarWipe(const XTransition *e) // by Ben Lucas
{ // License: MIT
    INIT_BEGIN
    ARG1(float, borderThickness, 0.01)
    ARG1(float, starRotation, 0.75)
    ARG4(vec4, borderColor, 1)
    VAR1(float, starAngle, M_2PIf / 5)
    INIT_END
    const float slope = 0.3f;
    vec2 r = rot2(sub2f(e->p, P5f), -starRotation * starAngle);
    float theta = atn2(r) + M_PIf;
    r = rot2(r, starAngle * (floorf(theta / starAngle) + P5f));
    r.x *= slope;
    float radius = (borderThickness * 2 + 1) * e->progress + r.x - borderThickness;
    if (radius > r.y && -radius < r.y)
        return e->b;
    radius += borderThickness;
    if (radius > r.y && -radius < r.y)
        return borderColor;
    return e->a;
}

static vec4 gl_static_wipe(const XTransition *e) // by Ben Lucas
{ // License: MIT
    INIT_BEGIN
    ARG1(bool, upToDown, 1)
    ARG1(float, maxSpan, 0.5)
    INIT_END
    float span = maxSpan * sqrtf(sinf(M_PIf * e->progress));
    float transitionEdge = upToDown ? 1 - e->p.y : e->p.y;
    float ss1 = smoothstep(e->progress - span, e->progress, transitionEdge);
    float ss2 = 1 - smoothstep(e->progress, e->progress + span, transitionEdge);
    float noiseEnvelope = ss1 * ss2;
    vec4 transitionMix = step(e->progress, transitionEdge) ? e->a : e->b;
    float d = frand2(mul2f(e->p, 1 + e->progress));
    vec4 noise = {{ d, d, d, transitionMix.p3 }};
    if (!e->k->is_rgb)
        noise.p1 = noise.p2 = P5f;
    return mix4(transitionMix, noise, noiseEnvelope);
}

static vec4 stereo_viewer(const XTransition *e, float zoom, float radius, bool flip, vec4 background, bool trkMat);
static vec4 gl_StereoViewer(const XTransition *e) // by Ted Schundler
{ // License: BSD 2-Clause
    INIT_BEGIN
    ARG1(float, zoom, 0.9)
    ARG1(float, radius, 0.25)
    ARG1(bool, flip, 0)
    ARG4(vec4, background, 0)
    ARG1(bool, trkMat, 0)
    INIT_END
    return stereo_viewer(e, zoom, radius, flip, background, trkMat); // licensed code
}

static vec4 gl_Stripe_Wipe(const XTransition *e) // by Boundless
{ // License: MIT
    INIT_BEGIN
    ARG1(int, nlayers, 3)
    ARG1(float, layerSpread, 0.5)
    ARG4(vec4, color1, 0x3319CCFF)
    ARG4(vec4, color2, 0x66CCFFFF)
    ARG1(float, shadowIntensity, 0.7)
    ARG1(float, shadowSpread, 0)
    ARG1(float, angle, 0)
    VAR1(float, rad, radians(angle))
    VAR1(float, offset, fabsf(sinf(rad)) + fabsf(cosf(rad) * e->ratio))
    INIT_END
    vec2 p = e->p;
    p.x = p.x * e->ratio - (e->ratio - 1) / 2;
    p = add2f(rot2(div2f(sub2f(p, P5f), offset), -rad), P5f);
    float px = cbrtf(1 - p.x);
    float lspread = (px + ((1 + layerSpread) * e->progress - 1)) * nlayers / layerSpread;
    float colorMix = (nlayers == 1) ? floorf(lspread) * 2 : floorf(lspread) / (nlayers - 1);
    float colorShade = fract(lspread) * shadowIntensity + shadowSpread;
    colorShade = 1 - clipUI(colorShade);
    if (colorMix >= 1 || colorMix < -2.f / nlayers || nlayers == 1) // colorMix == 1 for top stripe
        colorShade = 1;
    vec4 shadeComp = {{
        sinf(colorShade * M_PI_2f),
        sinf(clipUI(colorShade * 1.05f) * M_PI_2f),
        sinf(clipUI(colorShade * 1.3f) * M_PI_2f),
        1 }};
    if (betweenUI(colorMix)) {
        vec4 v = mix4(color1, color2, colorMix);
        v.p0 *= shadeComp.p0;
        if (e->k->is_rgb) // bend the stripe colour for RGB only
            v.p1 *= shadeComp.p1, v.p2 *= shadeComp.p2;
        return v;
    }
    vec4 colorComp = (e->progress > colorMix) ? e->a : e->b;
    if (colorMix < 0) {
        float m = clipUI(e->progress * 10);
        colorComp.p0 *= mixf(1, shadeComp.p0, m);
        if (e->k->is_rgb) {
            colorComp.p1 *= mixf(1, shadeComp.p1, m);
            colorComp.p2 *= mixf(1, shadeComp.p2, m);
        }
    }
    return colorComp;
}

static vec4 gl_swap(const XTransition *e) // by gre
{ // License: MIT
    INIT_BEGIN
    ARG1(float, reflection, 0.4)
    ARG1(float, perspective, 0.2)
    ARG1(float, depth, 3)
    ARG4(vec4, background, 0)
    INIT_END
    float size = mixf(1, depth, e->progress);
    float persp = perspective * e->progress;
    vec2 pfr = {
        e->p.x * size / (1 - persp),
        (e->p.y - P5f) * size / (1 - size * persp * e->p.x) + P5f
    };
    size = mixf(1, depth, 1 - e->progress);
    persp = perspective - persp;
    vec2 pto = {
        (e->p.x - 1) * size / (1 - persp) + 1,
        (e->p.y - P5f) * size / (1 - size * persp * (P5f - e->p.x)) + P5f
    };
    if (e->progress < P5f) {
        if (betweenUI2(pfr))
            return getFromColor(pfr);
        if (betweenUI2(pto))
            return getToColor(pto);
    }
    if (betweenUI2(pto))
        return getToColor(pto);
    if (betweenUI2(pfr))
        return getFromColor(pfr);
    // bgColor
    vec4 c = background;
    pfr.y = pfr.y * -1.2f - 0.02f;
    if (betweenUI2(pfr))
        return mix4(c, getFromColor(pfr), reflection * (1 - pfr.y));
    pto.y = pto.y * -1.2f - 0.02f;
    if (betweenUI2(pto))
        return mix4(c, getToColor(pto), reflection * (1 - pto.y));
    return c;
}

static vec4 gl_Swirl(const XTransition *e) // by Sergey Kosarevsky
{ // License: MIT
    INIT_BEGIN
    ARG1(float, radius, 1)
    INIT_END
    float T = e->progress;
    vec2 UV = sub2f(e->p, P5f);
    float Dist = length2(UV);
    if ( Dist < radius ) {
        float Percent = 1 - Dist / radius;
        float A = ((T <= P5f) ? T : 1 - T) * 2;
        float Theta = Percent * Percent * A * 8 * M_PIf;
        UV = rot2(UV, -Theta);
    }
    UV = add2f(UV, P5f);
    return mix4(getFromColor(UV), getToColor(UV), T);
}

static vec4 gl_WaterDrop(const XTransition *e) // by Paweł Płóciennik
{ // License: MIT
    INIT_BEGIN
    ARG1(float, amplitude, 30)
    ARG1(float, speed, 30)
    INIT_END
    vec2 dir = sub2f(e->p, P5f);
    float dist = length2(dir);
    if (dist > e->progress)
        return mix4(e->a, e->b, e->progress);
    float off = sinf(dist * amplitude - e->progress * speed);
    vec2 offset = add2(e->p, mul2f(dir, off));
    return mix4(getFromColor(offset), e->b, e->progress);
}

static vec4 gl_windowblinds(const XTransition *e) // by Fabien Benetou
{ // License: MIT
    INIT_END
    float t = glmod(floorf(e->p.y * 100 * e->progress), 2) ? e->progress * 1.5f : e->progress;
    return mix4(e->a, e->b, clipUI(mixf(t, e->progress, smoothstep(0.8f, 1, e->progress))));
}

// test transitions --------------------------------------------------

static vec4 test_blend(const XTransition *e)
{
    INIT_BEGIN
    ARG1(int, blendMode, NORMAL)
    INIT_END
    return (e->progress < P5f) ? blend(e, e->b, e->a, blendMode) : blend(e, e->a, e->b, blendMode);
}

static vec4 test_texture(const XTransition *e)
{
    INIT_BEGIN
    ARG4(vec4, background, 0)
    INIT_END
    return background;
}

// background textures --------------------------------------------------

// see https://www.shadertoy.com/view/S where S is Shadertoy ID, e.g. WdycRw

static vec4 t_cinetunnel(const XTransition *e) // by tomviolin (WdycRw)
{
    vec2 v = sub2f(e->p, P5f);
    float d = length2(v), a = -atn2(v) * 6, s = e->progress * 6; // speed
    float r = (sinf(a + M_2PIf * 2. / 3 + 4 / d + s) * P5f + P5f) * d * 2;
    float g  = (sinf(a + M_2PIf / 3 + 4 / d + s) * P5f + P5f) * d * 2;
    float b = (sinf(a + 4 / d + s) * P5f + P5f) * d * 2;
    float w = (sinf(a * 4 + M_2PIf / 3 + 3 / d + s) * P5f + P5f) * sinf(a * 7);
    w = ((w > .6f) ? 3 : 0) * d;
    return VEC3(w + g, w + b, w + r);
}

static vec4 t_diamond_pattern(const XTransition *e) // by rcread (ltX3W4)
{
    vec2 p = add2f(mul2f(abs2(sub2f(VEC2(e->p.x, e->p.y), P5f)), 800), 50);
    vec2 q = add2(p, p);
    float s = e->progress * 400, t;
    float r = (t = p.x + p.y, fabsf(t / 2 - fmodf(s, t)));
    float g = (t = q.x - p.y, fabsf(t / 2 - fmodf(s, t)));
    float b = (t = q.y - p.x, fabsf(t / 2 - fmodf(s, t)));
    return normalize3(VEC3(g, b, r));
}

static vec4 t_Glowing_thing(const XTransition *e) // by denzen (4lB3DG)
{
    vec2 p = e->p;
    float r = P5f - p.x, g = P5f - p.y, b;
    float t = e->progress * 5,
          z = atan2f(g, r) * 3,
          v = cosf(z + sinf(t * 0.1f)) + P5f + sinf(p.x * 10 + t * 1.3f) * 0.4f;
    r = 1.2 + cosf(z - t * 0.2f) + sinf(p.y * 10 + t * 1.5f) * P5f;
    g = sinf(v * 4) * 0.25f + r * P5f;
    b = sinf(v * 2) * 0.3f + r * P5f;
    return VEC3(g, b, r);
}

static vec4 t_glowingMarblingBlack(const XTransition *e) // by nasana (WtdXR8)
{
    vec2 p = e->p;
    float a = e->progress * 2 + 10;
    for (int i = 1; i < 10; i++) {
        p.x += 0.6f / i * cosf(i * 2.5f * p.y + a);
        p.y += 0.6f / i * cosf(i * 1.5f * p.x + a);
    }
    a = fabsf(sinf(a - p.y - p.x));
    return div3f(vec3f(0.1f), a);
}

static vec4 t_Monochrome_Hyperbola(const XTransition *e) // by MichaelPohoreski (Xtf3WN)
{
    //float t = e->k->duration * e->progress; // shader iTime
    vec2 p = sub2f(mul2f(e->p, 2), 1);
    float m = fract(atn2(p) + e->progress - 250 * logf(length2(p)));
    return vec3f(m > P5f);

}

static vec4 t_Natural_vignetting(const XTransition *e) // by ApoorvaJ (4lSXDm)
{
    float t = cosf(e->progress * M_2PIf) / 2 + 1;
    vec2 v = mul2f(sub2f(e->p, P5f), e->ratio * 2);
    float r = dot2(v, v) * t * t + 1;
    return vec3f(1 / (r * r));
}

static vec4 t_simple_plasma(const XTransition *e) // by Kastor (ldBGRR)
{
    float t = e->progress;
    vec2 p = sub2f(mul2f(e->p, 2), 1);
    float mov0 = p.x + p.y + cosf(sinf(t) * 2) * 100 + sinf(p.x * 0.01f) * 1000;
    float mov1 = p.y / 0.9f + t;
    float mov2 = p.x / 0.2f;
    float r = fabsf(sinf(mov1 + t) / 2 + mov2 / 2 - mov1 - mov2 + t);
    float g = fabsf(sinf(r + sinf(mov0 / 1440 + t) + sinf(p.y * 0.025f + t) + sinf((p.x + p.y) * 0.01f) * 3));
    float b = fabsf(sinf(g + cosf(mov1 + mov2 + g) + cosf(mov2) + sinf(p.x * 0.001f)));
    return VEC3(g, b, r);
}

static vec4 t_simple_rainbow_formula(const XTransition *e) // by Jodie (4l2cDm)
{
    float x = glmod(e->p.x + e->progress, 1);
    vec4 c = VEC3(sinf((x + 2.f / 3.f) * M_2PIf), sinf((x + 1.f / 3.f) * M_2PIf), sinf(x * M_2PIf));
    return add3f(mul3f(c, P5f), P5f);
}

static vec4 t_Skyline_in_132_chars(const XTransition *e) // by GregRostami (MtXSR7)
{
    float t = e->progress * 5;
    vec4 c = vec3f(0);
    for (int i = 1; i < 20; i++)
        if (e->p.y < sinf(ceilf(200.f * e->p.x / i + (i * i) + t)) - i * .04f)
            c = vec3f(i * .05f);
    return c;
}

static vec4 t_Skyline4(const XTransition *e) // by FabriceNeyret2 (XlsXRM)
{
    #define S(k) (d * sinf(k * x200 / b + 9.f * b + p5 / k))
    vec4 c;
    float x200 = e->p.x * 200, p5 = e->progress * 5;
    for (int b = 1; b < 22; b++) {
        float g = b * 0.03f, d = b * b * 0.0001f;
        if (e->p.y < 0.7f - g + S(1) * 2 + S(2) + S(5) / 2)
            c = VEC3(g, 1, 0);
        else
            c = add3f(c, .05f);
    }
    return c;
}

static vec4 t_spring_time(const XTransition *e) // by bergi (XllGDH)
{
    float t = e->progress * 0.75f;
    vec2 c = add2(mul2f(e->p, 0.2f + 0.05f * sinf(t * 1.1)),
                  mul2f(VEC2(2.2f + sinf(t), 0.4f * (1 + cosf(t * 0.9f))), 0.2f));
    for (int i = 0; i < 11; i++)
        c = sub2(div2f(abs2(c), dot2(c, c)), vec2f(0.81f - 0.1f * c.y));
    return VEC3(c.y * c.y, c.y - c.x, c.x * c.x);
}

static vec4 t_Water_Ripple(const XTransition *e) // by liucc09 (4cl3W4)
{
    float t = e->progress * 2, s = sinf(t), a = 1;
    vec4 m[] = { VEC3(-2, -1, 2), VEC3(3, -2, 1), VEC3(1, 2, 2) };
    vec4 c = VEC3(e->p.x * 7 + s, e->p.y * 7 + s, t);
    for (int i = 0; i < 3; i++) {
        c = mul3f(VEC3(dot3(c, m[0]), dot3(c, m[1]), dot3(c, m[2])), 0.3f);
        a = fminf(a, length3(sub3f(fract3(c), P5f)));
    }
    c = add3f(VEC3(0, 0.35f, 0.5f), powf(a, 7) * 25);
    return VEC3(c.p1, c.p2, c.p0);
}

////////////////////////////////////////////////////////////////////////////////
// background texture delegate
////////////////////////////////////////////////////////////////////////////////

static vec4 texture(const XTransition *e, int type)
{
    XTransition x;
    if (type & 1) // odd
        type += 1, x = *e, x.progress = P5f, e = &x;
    vec4 c;
    switch (type) {
        default: // fall-thru
        case -2: c = t_Natural_vignetting(e); break;
        case -4: c = t_glowingMarblingBlack(e); break;
        case -6: c = t_Monochrome_Hyperbola(e); break;
        case -8: c = t_Skyline_in_132_chars(e); break;
        case -10: c = t_simple_rainbow_formula(e); break;
        case -12: c = t_simple_plasma(e); break;
        case -14: c = t_diamond_pattern(e); break;
        case -16: c = t_Glowing_thing(e); break;
        case -18: c = t_cinetunnel(e); break;
        case -20: c = t_spring_time(e); break;
        case -22: c = t_Skyline4(e); break;
        case -24: c = t_Water_Ripple(e); break;
    }
    c.p3 = 1; // opaque
    return clipUI4(c);
}

////////////////////////////////////////////////////////////////////////////////
// easing delegate
////////////////////////////////////////////////////////////////////////////////

static float ease(XFadeContext *s, float progress)
{
    const XFadeEasingContext *k = s->k;
    if (!k->easingf)
        return progress; // uneased
    if (s->transition == CUSTOM) {
        // make uneased progess P available as ld(0), primarily for testing easing functions
        // horrible hack here due to incomplete definition of type 'struct AVExpr' at s->e
        // TODO: find a neat thread-safe way to implement this hook for slices
        typedef struct { // this must mimic struct AVExpr member sizeofs, see libavutil/eval.c
            int type;
            double value;
            int const_index;
            double (*func0)(double);
            struct AVExpr *param[3];
            double *var;
        } _AVExpr;
        _AVExpr *e = (_AVExpr*)s->e;
        e->var[0] = progress;
    };
    return 1 - k->easingf(k, 1 - progress); // (1 to 0 for xfade)
}

////////////////////////////////////////////////////////////////////////////////
// extended transition delegate
////////////////////////////////////////////////////////////////////////////////

#define XTRANSITION_TRANSITION(name, type, div)                                \
static void xtransition##name##_transition(AVFilterContext *ctx,               \
                                           const AVFrame *a, const AVFrame *b, \
                                           AVFrame *out,                       \
                                           float progress,                     \
                                           int slice_start, int slice_end,     \
                                           int jobnr)                          \
{                                                                              \
    const XFadeContext *s = ctx->priv;                                         \
    const XFadeEasingContext *k = s->k;                                        \
    const float mw = k->mw, mh = k->mh, mv = k->mv; /* as float */             \
    XTransition e = { /* slice data */                                         \
        .progress = 1 - progress, /* 0 to 1 for xtransitions */                \
        .ratio = k->r, /* pixel ratio */                                       \
        .k = k /* common context */                                            \
    };                                                                         \
    /* pixel iterator and unit interval conversions */                         \
    for (int y = slice_start; y < slice_end; y++) {                            \
        e.p.y = 1 - y / mh; /* y=0 is bottom */                                \
        for (int x = 0, p = 0; x <= k->mw; x++) {                              \
            e.p.x = x / mw;                                                    \
            e.a = e.b = VEC4(0, P5f, P5f, 1); /* plane defaults */             \
            do {                                                               \
                e.a.p[p] = line##div(a, p, y)[x] / mv; /* from colour */       \
                e.b.p[p] = line##div(b, p, y)[x] / mv; /* to colour */         \
            } while (++p < k->n);                                              \
            vec4 c = k->xtransitionf(&e); /* transition colour */              \
            do {                                                               \
                --p;                                                           \
                line##div(out, p, y)[x] = scaleUI(c.p[p], k->mv); /* clips */  \
            } while (p > 0);                                                   \
        }                                                                      \
    }                                                                          \
}

XTRANSITION_TRANSITION(8, uint8_t, 1)
XTRANSITION_TRANSITION(16, uint16_t, 2)

////////////////////////////////////////////////////////////////////////////////
// argument parsing
////////////////////////////////////////////////////////////////////////////////

// emit error message, reduces verbosity
static int xe_error(void *avcl, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    av_vlog(avcl, AV_LOG_ERROR, fmt, args);
    va_end(args);
    return AVERROR(EINVAL);
}

// emit warning message
static void xe_warning(void *avcl, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    av_vlog(avcl, AV_LOG_WARNING, fmt, args);
    va_end(args);
}

// emit debug message
static void xe_debug(void *avcl, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    av_log(avcl, AV_LOG_DEBUG, "xfade-easing: ");
    av_vlog(avcl, AV_LOG_DEBUG, fmt, args);
    va_end(args);
}

// remove extraneous spaces in place
static void rmspace(char *s)
{
    char *d = s;
    char c, l = 0;
    while ((c = *s++)) {
        // trim name part
        if (c != '(') {
            if (c != ' ')
                l = c;
            *d++ = c;
            continue;
        }
        if (l)
            while (d[-1] != l)
                d--;
        *d++ = l = c;
        // trim args allowing single space between CSV tokens
        bool b = 0, e;
        while ((c = *s++)) {
            if (c != ' ' || (b && l != ' ')) {
                if ((e = (c == ',' || c == ')')))
                    if (b && l == ' ')
                        d--;
                b = !e;
                *d++ = l = c;
            }
        }
        break;
    }
    *d = 0;
}

// like strtok_r but doesn't skip empty values between commas
static char *csvtok(char *s, char **p)
{
    char *c = s ? s : (s = *p);
    if (!*c)
        return NULL;
    while (*c) {
        if (*c++ == ',') {
            c[-1] = 0;
            break;
        }
    }
    *p = c;
    return s;
}

// parse a number or colour
static double argv(char *s, char **p)
{
    char *c;
    double d = strtod(s, &c); // try number (inc. grey)
    if (*s == '#' || !strncmp(s, "0x", 2) || isalpha(*s) || strchr(s, '@')) { // try colour
        c = s;
        uint8_t rgba[4];
        if (!av_parse_color(rgba, s, -1, NULL)) { // (fails for 0X prefix)
            uint32_t u = rgba[0] << 24 | rgba[1] << 16 | rgba[2] << 8 | rgba[3];
            uint64_t l = u | 1ULL << 32; // colour flag bit 32 ensures value > 1
            d = l;
            c += strlen(s);
        }
    }
    *p = c;
    return d;
}

// standard/supplementary easing mode
static int parse_standard_easing(AVFilterContext *ctx, char *args)
{
    XFadeContext *s = ctx->priv;
    struct Standard *a = &s->k->eargs.e;
    s->k->eargs.type = STANDARD;
    char *p = strchr(s->easing_str, '-');
    if (!p) a->mode = EASE_INOUT;
    else if (!av_strcasecmp(p, "-in-out")) a->mode = EASE_INOUT;
    else if (!av_strcasecmp(p, "-in")) a->mode = EASE_IN;
    else if (!av_strcasecmp(p, "-out")) a->mode = EASE_OUT;
    else return xe_error(ctx, "unknown easing function %s\n", s->easing_str);
    if (args)
        xe_warning(ctx, "ignoring extraneous easing arguments %s\n", args);
    xe_debug(ctx, "easing = %s[%d]\n", s->easing_str, a->mode);
    return 0;
}

// CSS linear()
static int parse_linear_easing(AVFilterContext *ctx, char *args)
{
    if (!args)
        return 0;
    XFadeContext *s = ctx->priv;
    struct Linear *a = &s->k->eargs.l;
    s->k->eargs.type = LINEAR;
    // parse
    char *e, *c, *b, *t;
    float d = -FLT_MAX; // ensure x increases
    while ((e = csvtok(args, &c))) { // each arg
        if (!*e)
            return xe_error(ctx, "expected number in easing option\n");
        e = av_strtok(e, " ", &b);
        float x = NAN, y = strtof(e, &t);
        if (t == e || *t != 0)
            return xe_error(ctx, "bad number %s in easing option\n", e);
        int i, n = 1;
        vec2 q[2];
        for (i = 0; i < 2; i++) {
            if ((e = av_strtok(NULL, " ", &b))) { // have %
                x = strtof(e, &t);
                if (t == e || *t != '%')
                    return xe_error(ctx, "bad number %s in easing option\n", e);
                x = d = fmaxf(x * 0.01f, d);
                if (i)
                    n++;
            }
            q[i] = VEC2(x, y);
        }
        if (!(a->points = av_realloc_array(a->points, a->stops + n, sizeof(*a->points))))
            return AVERROR(ENOMEM);
        for (i = 0; i < n; i++)
            a->points[a->stops++] = q[i];
        args = NULL;
    }
    // interpolate x gaps
    int n = a->stops;
    if (n < 2)
        return xe_error(ctx, "expected at least 2 easing arguments, got %d\n", n);
    vec2 *p = a->points;
    if (isnan(p[0].x))
        p[0].x = 0;
    if (isnan(p[n - 1].x))
        p[n - 1].x = 1;
    for (int i = 1, j = 0; i < n; i++) {
        float x = p[i].x;
        if (!isnan(x)) {
            if (i - j > 1) {
                d = (x - p[j].x) / (i - j);
                for (j++; j < i; j++)
                    p[j].x = p[j - 1].x + d;
                p[j].x = x;
            }
            j = i;
        }
    }
    xe_debug(ctx, "easing = %s[%d](", s->easing_str, n);
    for (int i = 0; i < n; i++)
        av_log(ctx, AV_LOG_DEBUG, "%s%g %g", i ? ", " : "", a->points[i].x, a->points[i].y);
    av_log(ctx, AV_LOG_DEBUG, ")\n");
    return 0;
}

// CSS cubic-bezier()
static int parse_cubic_bezier_easing(AVFilterContext *ctx, char *args)
{
    XFadeContext *s = ctx->priv;
    union Bezier *a = &s->k->eargs.b;
    s->k->eargs.type = BEZIER;
    int i = 0;
    if (args) {
        char *e, *c, *t;
        for (; (e = csvtok(args, &c)); i++) { // each arg
            float v = strtof(e, &t);
            if (t == e)
                return xe_error(ctx, "bad number %s in easing option\n", e);
            if (i < 4)
                a->p[i] = v;
            args = NULL;
        }
    }
    if (i != 4)
        return xe_error(ctx, "expected 4 easing arguments, got %d\n", i);
    xe_debug(ctx, "easing = %s(%g, %g, %g, %g)\n", s->easing_str, a->x1, a->y1, a->x2, a->y2);
    return 0;
}

// CSS steps()
static int parse_steps_easing(AVFilterContext *ctx, char *args)
{
    if (!args)
        return xe_error(ctx, "expected 2 easing parameters\n");
    XFadeContext *s = ctx->priv;
    struct Steps *a = &s->k->eargs.s;
    s->k->eargs.type = STEPS;
    char *e, *c, *t;
    e = csvtok(args, &c);
    if (!e)
        return xe_error(ctx, "expected 2 easing parameters\n");
    a->position = JUMP_END; // default
    a->steps = strtoul(e, &t, 10);
    if (t == e)
        return xe_error(ctx, "bad number %s in easing option\n", e);
    if ((e = csvtok(NULL, &c))) {
        if (!av_strcasecmp(e, "jump-start") || !av_strcasecmp(e, "start"))
            a->position = JUMP_START;
        else if (!av_strcasecmp(e, "jump-none"))
            a->position = JUMP_NONE;
        else if (!av_strcasecmp(e, "jump-both"))
            a->position = JUMP_BOTH;
        else if (av_strcasecmp(e, "jump-end") && av_strcasecmp(e, "end"))
            return xe_error(ctx, "bad parameter %s in easing option\n", e);
    }
    if (a->steps < 1 || (a->position == JUMP_NONE && a->steps < 2))
        return xe_error(ctx, "bad value %d in easing option\n", a->steps);
    xe_debug(ctx, "easing = %s(%d, %d)\n", s->easing_str, a->steps, a->position);
    return 0;
}

// easing name and customisation arguments
static int parse_easing(AVFilterContext *ctx)
{
    XFadeContext *s = ctx->priv;
    XFadeEasingContext *k = s->k;

    if (!s->easing_str)
        return 0; // uneased

    rmspace(s->easing_str);
    xe_debug(ctx, "parse_easing '%s'\n", s->easing_str);

    char *e = s->easing_str, *c;
    if ((c = strchr(e, '(')) && !strchr(c, ')'))
        return xe_error(ctx, "missing ')' in easing option %s\n", e);

    e = av_strtok(e, "(", &c);
    if (!e)
        return xe_error(ctx, "missing easing function name\n");

    int (*f)(AVFilterContext *ctx, char *args) = NULL;
    const char *p = NULL;
    EasingArgs *a = &k->eargs;
    // match exact
         if (!av_strcasecmp(e, "linear")) k->easingf = css_linear, f = parse_linear_easing;
    else if (!av_strcasecmp(e, "cubic-bezier")) k->easingf = css_cubic_bezier, f = parse_cubic_bezier_easing;
    else if (!av_strcasecmp(e, "ease")) k->easingf = css_cubic_bezier, a->b = (union Bezier) {{ 0.25, 0.1, 0.25, 1. }};
    else if (!av_strcasecmp(e, "ease-in")) k->easingf = css_cubic_bezier, a->b = (union Bezier) {{ 0.42, 0., 1., 1. }};
    else if (!av_strcasecmp(e, "ease-out")) k->easingf = css_cubic_bezier, a->b = (union Bezier) {{ 0., 0., 0.58, 1. }};
    else if (!av_strcasecmp(e, "ease-in-out")) k->easingf = css_cubic_bezier, a->b = (union Bezier) {{ 0.42, 0., 0.58, 1. }};
    else if (!av_strcasecmp(e, "steps")) k->easingf = css_steps, f = parse_steps_easing;
    else if (!av_strcasecmp(e, "step-start")) k->easingf = css_steps, a->s = (struct Steps) { 1, JUMP_START };
    else if (!av_strcasecmp(e, "step-end")) k->easingf = css_steps, a->s = (struct Steps) { 1, JUMP_END };
    // match prefix
    else if (av_stristart(e, "quadratic", &p)) k->easingf = rp_quadratic;
    else if (av_stristart(e, "cubic", &p)) k->easingf = rp_cubic;
    else if (av_stristart(e, "quartic", &p)) k->easingf = rp_quartic;
    else if (av_stristart(e, "quintic", &p)) k->easingf = rp_quintic;
    else if (av_stristart(e, "sinusoidal", &p)) k->easingf = rp_sinusoidal;
    else if (av_stristart(e, "exponential", &p)) k->easingf = rp_exponential;
    else if (av_stristart(e, "circular", &p)) k->easingf = rp_circular;
    else if (av_stristart(e, "elastic", &p)) k->easingf = rp_elastic;
    else if (av_stristart(e, "back", &p)) k->easingf = rp_back;
    else if (av_stristart(e, "bounce", &p)) k->easingf = rp_bounce;
    else if (av_stristart(e, "squareroot", &p)) k->easingf = se_squareroot;
    else if (av_stristart(e, "cuberoot", &p)) k->easingf = se_cuberoot;
    if (p) {
        if (!*p || *p == '-')
            f = parse_standard_easing;
        else
            k->easingf = NULL;
    }
    if (!k->easingf)
        return xe_error(ctx, "unknown easing function %s\n", e);

    e = av_strtok(NULL, ")", &c);
    if (f)
        return f(ctx, e); // parse args

    return 0;
}

// extended transition name and customisation arguments
static int parse_xtransition(AVFilterContext *ctx)
{
    XFadeContext *s = ctx->priv;
    XFadeEasingContext *k = s->k;

    rmspace(s->transition_str);
    xe_debug(ctx, "parse_xtransition '%s'\n", s->transition_str);

    for (const AVOption *o = xfade_options; o->name; o++) { // try xfade transition
        if (!o->offset && !strcmp(o->unit, "transition") && !av_strcasecmp(o->name, s->transition_str)) {
            s->transition = o->default_val.i64;
            return 1; // to resume vf_xfade:config_output()
        }
    }

    char *t = s->transition_str, *c, *p;
    if ((c = strchr(t, '(')) && !strchr(c, ')'))
        return xe_error(ctx, "missing ')' in transition option %s\n", t);

    t = av_strtok(t, "(", &c);
    if (!t)
        return xe_error(ctx, "missing extended transition name\n");

         if (!av_strcasecmp(t, "gl_angular")) k->xtransitionf = gl_angular;
    else if (!av_strcasecmp(t, "gl_Bars")) k->xtransitionf = gl_Bars;
    else if (!av_strcasecmp(t, "gl_blend")) k->xtransitionf = gl_blend;
    else if (!av_strcasecmp(t, "gl_BookFlip")) k->xtransitionf = gl_BookFlip;
    else if (!av_strcasecmp(t, "gl_Bounce")) k->xtransitionf = gl_Bounce;
    else if (!av_strcasecmp(t, "gl_BowTie")) k->xtransitionf = gl_BowTie;
    else if (!av_strcasecmp(t, "gl_ButterflyWaveScrawler")) k->xtransitionf = gl_ButterflyWaveScrawler;
    else if (!av_strcasecmp(t, "gl_cannabisleaf")) k->xtransitionf = gl_cannabisleaf;
    else if (!av_strcasecmp(t, "gl_chessboard")) k->xtransitionf = gl_chessboard;
    else if (!av_strcasecmp(t, "gl_CornerVanish")) k->xtransitionf = gl_CornerVanish;
    else if (!av_strcasecmp(t, "gl_CrazyParametricFun")) k->xtransitionf = gl_CrazyParametricFun;
    else if (!av_strcasecmp(t, "gl_crosshatch")) k->xtransitionf = gl_crosshatch;
    else if (!av_strcasecmp(t, "gl_CrossOut")) k->xtransitionf = gl_CrossOut;
    else if (!av_strcasecmp(t, "gl_crosswarp")) k->xtransitionf = gl_crosswarp;
    else if (!av_strcasecmp(t, "gl_CrossZoom")) k->xtransitionf = gl_CrossZoom;
    else if (!av_strcasecmp(t, "gl_cube")) k->xtransitionf = gl_cube;
    else if (!av_strcasecmp(t, "gl_Diamond")) k->xtransitionf = gl_Diamond;
    else if (!av_strcasecmp(t, "gl_DirectionalScaled")) k->xtransitionf = gl_DirectionalScaled;
    else if (!av_strcasecmp(t, "gl_directionalwarp")) k->xtransitionf = gl_directionalwarp;
    else if (!av_strcasecmp(t, "gl_doorway")) k->xtransitionf = gl_doorway;
    else if (!av_strcasecmp(t, "gl_DoubleDiamond")) k->xtransitionf = gl_DoubleDiamond;
    else if (!av_strcasecmp(t, "gl_Dreamy")) k->xtransitionf = gl_Dreamy;
    else if (!av_strcasecmp(t, "gl_EdgeTransition")) k->xtransitionf = gl_EdgeTransition;
    else if (!av_strcasecmp(t, "gl_Exponential_Swish")) k->xtransitionf = gl_Exponential_Swish;
    else if (!av_strcasecmp(t, "gl_FanIn")) k->xtransitionf = gl_FanIn;
    else if (!av_strcasecmp(t, "gl_FanOut")) k->xtransitionf = gl_FanOut;
    else if (!av_strcasecmp(t, "gl_FanUp")) k->xtransitionf = gl_FanUp;
    else if (!av_strcasecmp(t, "gl_Flower")) k->xtransitionf = gl_Flower;
    else if (!av_strcasecmp(t, "gl_GridFlip")) k->xtransitionf = gl_GridFlip;
    else if (!av_strcasecmp(t, "gl_heart")) k->xtransitionf = gl_heart;
    else if (!av_strcasecmp(t, "gl_hexagonalize")) k->xtransitionf = gl_hexagonalize;
    else if (!av_strcasecmp(t, "gl_InvertedPageCurl")) k->xtransitionf = gl_InvertedPageCurl;
    else if (!av_strcasecmp(t, "gl_kaleidoscope")) k->xtransitionf = gl_kaleidoscope;
    else if (!av_strcasecmp(t, "gl_Lissajous_Tiles")) k->xtransitionf = gl_Lissajous_Tiles;
    else if (!av_strcasecmp(t, "gl_morph")) k->xtransitionf = gl_morph;
    else if (!av_strcasecmp(t, "gl_Mosaic")) k->xtransitionf = gl_Mosaic;
    else if (!av_strcasecmp(t, "gl_perlin")) k->xtransitionf = gl_perlin;
    else if (!av_strcasecmp(t, "gl_pinwheel")) k->xtransitionf = gl_pinwheel;
    else if (!av_strcasecmp(t, "gl_polar_function")) k->xtransitionf = gl_polar_function;
    else if (!av_strcasecmp(t, "gl_PolkaDotsCurtain")) k->xtransitionf = gl_PolkaDotsCurtain;
    else if (!av_strcasecmp(t, "gl_powerKaleido")) k->xtransitionf = gl_powerKaleido;
    else if (!av_strcasecmp(t, "gl_randomNoisex")) k->xtransitionf = gl_randomNoisex;
    else if (!av_strcasecmp(t, "gl_randomsquares")) k->xtransitionf = gl_randomsquares;
    else if (!av_strcasecmp(t, "gl_ripple")) k->xtransitionf = gl_ripple;
    else if (!av_strcasecmp(t, "gl_Rolls")) k->xtransitionf = gl_Rolls;
    else if (!av_strcasecmp(t, "gl_RotateScaleVanish")) k->xtransitionf = gl_RotateScaleVanish;
    else if (!av_strcasecmp(t, "gl_rotateTransition")) k->xtransitionf = gl_rotateTransition;
    else if (!av_strcasecmp(t, "gl_rotate_scale_fade")) k->xtransitionf = gl_rotate_scale_fade;
    else if (!av_strcasecmp(t, "gl_SimpleBookCurl")) k->xtransitionf = gl_SimpleBookCurl;
    else if (!av_strcasecmp(t, "gl_SimplePageCurl")) k->xtransitionf = gl_SimplePageCurl;
    else if (!av_strcasecmp(t, "gl_Slides")) k->xtransitionf = gl_Slides;
    else if (!av_strcasecmp(t, "gl_squareswire")) k->xtransitionf = gl_squareswire;
    else if (!av_strcasecmp(t, "gl_StarWipe")) k->xtransitionf = gl_StarWipe;
    else if (!av_strcasecmp(t, "gl_static_wipe")) k->xtransitionf = gl_static_wipe;
    else if (!av_strcasecmp(t, "gl_StereoViewer")) k->xtransitionf = gl_StereoViewer;
    else if (!av_strcasecmp(t, "gl_Stripe_Wipe")) k->xtransitionf = gl_Stripe_Wipe;
    else if (!av_strcasecmp(t, "gl_swap")) k->xtransitionf = gl_swap;
    else if (!av_strcasecmp(t, "gl_Swirl")) k->xtransitionf = gl_Swirl;
    else if (!av_strcasecmp(t, "gl_WaterDrop")) k->xtransitionf = gl_WaterDrop;
    else if (!av_strcasecmp(t, "gl_windowblinds")) k->xtransitionf = gl_windowblinds;
    else if (!av_strcasecmp(t, "test_blend")) k->xtransitionf = test_blend;
    else if (!av_strcasecmp(t, "test_texture")) k->xtransitionf = test_texture;
    else return xe_error(ctx, "unknown extended transition name %s\n", t);

    XTransitionArgs *a = &k->targs;
    if ((p = av_strtok(NULL, ")", &c))) { // has args
        while ((t = csvtok(p, &c))) { // next arg
            if (!(a->argv = av_realloc_array(a->argv, ++a->argc, sizeof(*a->argv))))
                return AVERROR(ENOMEM);
            struct Argv *v = &a->argv[a->argc - 1];
            v->param = NULL;
            v->value = NAN; // use default
            if (*t) { // not empty
                if ((p = strchr(t, '='))) { // named
                    *p++ = 0;
                    v->param = t;
                    t = p;
                }
                v->value = argv(t, &p);
                if (p == t)
                    return xe_error(ctx, "invalid value %s in transition option\n", t);
            }
            p = NULL;
        }
    }
    xe_debug(ctx, "transition_str = %s(", s->transition_str);
    for (int i = 0; i < a->argc; i++)
        av_log(ctx, AV_LOG_DEBUG, "%s%s=%g", i ? ", " : "", a->argv[i].param, a->argv[i].value);
    av_log(ctx, AV_LOG_DEBUG, ")\n");

    return 0;
}

////////////////////////////////////////////////////////////////////////////////
// configuration
////////////////////////////////////////////////////////////////////////////////

// install
static int config_xfade_easing(AVFilterContext *ctx)
{
    xe_debug(ctx, "config_xfade_easing\n");
    XFadeContext *s = ctx->priv;
    XFadeEasingContext *k;
    int ret;

    if (!(k = av_mallocz(sizeof(XFadeEasingContext))))
        return AVERROR(ENOMEM);
    s->k = k;
    k->s = s;

    ret = parse_easing(ctx);
    if (ret < 0)
        return ret;

    ret = parse_xtransition(ctx);
    if (ret != 0)
        return ret; // 1 if xfade transition

    AVFilterLink *l = ctx->outputs[0];
#if LIBAVFILTER_VERSION_INT < AV_VERSION_INT(10, 4, 100)
    k->framerate = r2f(l->frame_rate); // v6.x, v7.0
#else
    k->framerate = r2f(ff_filter_link(l)->frame_rate); // v7.1
#endif
    k->duration = (float)s->duration / AV_TIME_BASE; // seconds
    k->r = (float)l->w / l->h;
    k->n = s->nb_planes;
    k->mw = l->w - 1;
    k->mh = l->h - 1;
    k->mv = s->max_value;
    k->is_rgb = s->is_rgb;
    k->is_16 = s->depth > 8;
    s->transitionf = k->is_16 ? xtransition16_transition: xtransition8_transition;

    XTransition e = { .k = k, .ratio = k->r };
    k->xtransitionf(&e); // cache transition parameters and constants
    k->init = true;

    xe_debug(ctx, "XFadeEasingContext: .framerate=%g .duration=%g .r=%g .n=%d\n .mw=%d .mh=%d .mv=%d .is_16=%d .is_rgb=%d\n",
             k->framerate, k->duration, k->r, k->n, k->mw, k->mh, k->mv, k->is_16, k->is_rgb);

    return 0;
}

// uninstall
static void xe_data_free(XFadeEasingContext *k)
{
    xe_debug(NULL, "xe_data_free\n");
    if (!k) return;
    if (k->eargs.type == LINEAR && k->eargs.l.points)
        av_free(k->eargs.l.points);
    if (k->targs.argv)
        av_free(k->targs.argv);
    av_freep(&k);
}

////////////////////////////////////////////////////////////////////////////////
// licensed code
////////////////////////////////////////////////////////////////////////////////

/*
Copyright (c) 2010 Hewlett-Packard Development Company, L.P. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
    3. Neither the name of the copyright holder nor the names of its
       contributors may be used to endorse or promote products derived from this
       software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
// Refactored from
// https://github.com/gl-transitions/gl-transitions/blob/master/transitions/InvertedPageCurl.glsl
// see https://webvfx.rectalogic.com/examples_2transition-shader-pagecurl_8html-example.html
// omits anti-alias code
static vec4 inverted_page_curl(const XTransition *e, int angle, float radius, bool reverseEffect)
{
    #define MIN_AMOUNT -0.16f
    #define MAX_AMOUNT 1.5f
    const float amount = (reverseEffect ? (1 - e->progress) : e->progress) * (MAX_AMOUNT - MIN_AMOUNT) + MIN_AMOUNT;
    const float cylinderAngle = M_2PIf * amount;
    const float cylinderRadius = radius;
    const float ang = radians(angle);
    vec2 o1 = { -0.801, 0.89 }, o2 = { 0.985, 0.985 }; // for 100 degrees
    if (angle == 30) // values from WebVfx link
        o1 = VEC2(0.12, 0.258), o2 = VEC2(0.15, -0.5); // from WebVfx link
    vec2 point = add2(rot2(e->p, ang), o1), p;
    float yc = point.y - amount, hitAngle;
    vec4 colour = reverseEffect ? e->b : e->a;
    if (yc > cylinderRadius) // flat surface
        return colour;
    if (yc < -cylinderRadius) { // behind surface
        // behindSurface()
        yc = -cylinderRadius - cylinderRadius - yc;
        hitAngle = acosf(yc / cylinderRadius) + cylinderAngle - M_PIf;
        p = VEC2(point.x, hitAngle * M_1_2PIf);
        point = add2(rot2(p, -ang), o2);
        colour = reverseEffect ? e->a : e->b;
        if (yc < 0 && betweenUI2(point) && (hitAngle < M_PIf || amount > P5f)) { // shadow over to page
            float shadow = (1 - length2(sub2f(point, P5f)) * M_SQRT2f) * powf(-yc / cylinderRadius, 3) / 2;
            colour.p0 -= shadow; // (can go -ve)
            if (e->k->is_rgb)
                colour.p1 -= shadow, colour.p2 -= shadow;
        }
        return colour;
        // end behindSurface()
    }
    // seeThrough()
    hitAngle = M_PIf - acosf(yc / cylinderRadius) + cylinderAngle;
    if (yc < 0) { // get from colour going through its turn
        p = VEC2(point.x, hitAngle * M_1_2PIf);
        vec2 q = add2(rot2(p, -ang), o2);
        bool r = betweenUI2(q);
        if (reverseEffect)
            colour = r ? getToColor(q) : e->a;
        else
            colour = r ? getFromColor(q) : e->b;
    }
    // end seeThrough()
    hitAngle = cylinderAngle + cylinderAngle - hitAngle;
    float hitAngleMod = glmod(hitAngle, M_2PIf);
    if ((hitAngleMod > M_PIf && amount < P5f) || (hitAngleMod > M_PI_2f && amount < 0))
        return colour;
    p = VEC2(point.x, hitAngle * M_1_2PIf);
    point = add2(rot2(p, -ang), o2);
    // seeThroughWithShadow()
    // distanceToEdge()
    float dx = (point.x < 0) ? -point.x : (point.x > 1) ? point.x - 1 : (point.x > P5f) ? 1 - point.x : point.x;
    float dy = (point.y < 0) ? -point.y : (point.y > 1) ? point.y - 1 : (point.y > P5f) ? 1 - point.y : point.y;
    float dist = (betweenUI(point.x) || betweenUI(point.y)) ? fminf(dx, dy) : hypotf(dx, dy);
    // end distanceToEdge()
    float shadow = (1 - dist * 30) / 3;
    if (shadow > 0) { // shadow over from page
        shadow *= amount;
        colour.p0 -= shadow;
        if (e->k->is_rgb)
            colour.p1 -= shadow, colour.p2 -= shadow;
    }
    // end seeThroughWithShadow()
    if (!betweenUI2(point))
        return colour;
    // backside
    colour = reverseEffect ? getToColor(point) : getFromColor(point);
    float g = colour.p0;
    if (e->k->is_rgb)
        g = (g + colour.p1 + colour.p2) / 3; // simple average
    g *= 0.2f;
    g += 0.8f * (powf(1 - fabsf(yc / cylinderRadius), 0.2f) / 2 + P5f);
    colour.p0 = g;
    colour.p1 = colour.p2 = e->k->is_rgb ? g : P5f;
    return colour;
}

/*
Copyright (c) 2016, Theodore K Schundler. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
OF THE POSSIBILITY OF SUCH DAMAGE.
*/
// Stereo Viewer Toy Transition
// Inspired by ViewMaster / Image3D image viewer devices
// This effect is similar to what you see when you press the device's lever
//
// Refactored, simplified and enhanced by Raymond Luckhurst from
// https://github.com/gl-transitions/gl-transitions/blob/master/transitions/StereoViewer.glsl

static inline bool in_rounded_mask(vec2 c, vec2 r)
{
    c = div2(add2(abs2(c), sub2f(r, P5f)), r);
    return (c.x < 0 && c.y < 1) || (c.y < 0 && c.x < 1) || dot2(c, c) < 1;
}
static inline vec4 unscreen(vec4 c) // colour when screened with itself yields original colour
{
    float a = c.p3;
    c = cpl3(sqrt3(cpl3(c)));
    c.p3 = a;
    return c;
}
static vec4 stereo_viewer(const XTransition *e, float zoom, float radius, bool flip, vec4 background, bool trkMat)
{
    vec2 c = sub2f(e->p, P5f), z; // point from centre
    float angle;
    vec4 img, img0, img1;
    vec2 r = { radius / e->ratio, radius }; // radius warped for square aspect
    // time sequence
    if (e->progress < 0.1f || e->progress >= 0.9f) {
        // 0.0-0.1: zoom out and round the corners
        // 0.9-1.0: zoom in and square the corners
        angle = (P5f - fabsf(P5f - e->progress)) * 10;
        z = div2f(c, 1 + angle * (zoom - 1));
        if (in_rounded_mask(z, mul2f(r, angle))) {
            z = add2f(z, P5f);
            img = (e->progress < P5f) ? getFromColor(z) : getToColor(z);
            if (!trkMat || step(background.p3, img.p3)) // alpha tracking
                return img;
        }
    } else if (e->progress < 0.48f || e->progress >= 0.52f) {
        // 0.1-0.48: split image and rotate up and down along off-screen pivot points
        // 0.48-0.52: background
        // 0.52-0.9: image stays put but the two masks move
        if (e->progress > P5f) // if zoomed out test if point within centred mask
            if (!in_rounded_mask(z = div2f(c, zoom), r))
                return background;
        // test if point within rotated masks
        angle = 1 - (fabsf(P5f - e->progress) - 0.02f) / 0.38f;
        angle *= angle; // easing
        angle /= lerp(1.23f, zoom, -1.6f); // empirical radians
        if (flip)
            angle = -angle;
        float offset = 2; // pivot offset
        bool m[2]; // masks
        vec2 t[2]; // translated points
        for (int i = 0; i < 2; i++) { // each mask
            vec2 q = c;
            q.x = q.x * e->ratio + offset;
            q = rot2(q, -angle);
            q.x = (q.x - offset) / e->ratio;
            q = div2f(q, zoom);
            m[i] = in_rounded_mask(t[i] = q, r);
            offset = -offset;
        }
        if (!m[0] && !m[1]) // outside masks
            return background;
        // get point colours
        if (e->progress < P5f) {
            if (m[0])
                img0 = getFromColor(add2f(t[0], P5f));
            if (m[1])
                img1 = getFromColor(add2f(t[1], P5f));
        } else {
            img = getToColor(add2f(z, P5f));
        }
        // masking logic
        if (trkMat) { // alpha tracking
            // foreground alpha shows background when fg.a <= bg.a (good for transparent cutouts)
            if (e->progress < P5f) {
                m[0] = m[0] && step(background.p3, img0.p3) && img0.p3 != 0;
                m[1] = m[1] && step(background.p3, img1.p3) && img1.p3 != 0;
                if (!m[0] && !m[1])
                    return background;
            } else {
                if (!step(background.p3, img.p3))
                    return background;
            }
        }
        // legacy behaviour (modified)
        if (e->progress < P5f) {
            if (m[0] && m[1])
                return blend(e, unscreen(img0), unscreen(img1), SCREEN);
            img = m[0] ? img0 : img1;
        } else {
            if (m[0] && m[1])
                return img;
        }
        return mix4(background, img, 0.8f);
    }
    return background;
}

/*
Copyright (C) 2008 Apple Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
OF THE POSSIBILITY OF SUCH DAMAGE.
*/
// This is refactored WebKit C++ code from UnitBezier.h shrunk, optimised and precision reduced to float
// WebKit: https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/graphics/UnitBezier.h
// called by https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/animation/TimingFunction.cpp
// see also:
// Chromium CC: https://chromium.googlesource.com/chromium/src/+/master/ui/gfx/geometry/cubic_bezier.cc
// Gecko: https://github.com/mozilla/gecko-dev/blob/master/dom/smil/SMILKeySpline.cpp
//        https://github.com/mozilla/gecko-dev/blob/master/servo/components/style/bezier.rs
// good explanation at https://probablymarcus.com/blocks/2015/02/26/using-bezier-curves-as-easing-functions.html
static float solve_cubic_bezier(float x1, float y1, float x2, float y2, float x, float epsilon)
{
    float t, s, d;
    // end-point gradients
    if (x < 0) { // (never for easing)
        d = (x1 > 0) ? y1 / x1 : (y1 == 0 && x2 > 0) ? y2 / x2 : (y1 == 0 && y2 == 0); // start
        return 0 + d * x;
    }
    if (x > 1) { // (never for easing)
        d = (x2 < 1) ? (y2 - 1) / (x2 - 1) : (y2 == 1 && x1 < 1) ? (y1 - 1) / (x1 - 1) : (y2 == 1 && y1 == 1); // end
        return 1 + d * (x - 1);
    }
    // polynomial coefficients
    const float cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx,
                cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    // find t, the parametric value x came from
    int i;
    // linear interpolation of spline curve for initial guess
    #define NB_SPLINE_SAMPLES 11
    const float dt = 1.f / (NB_SPLINE_SAMPLES - 1); // delta
    float t0 = 0, t1 = 1;
    for (t = dt, i = 1; i < NB_SPLINE_SAMPLES - 1; t += dt, i++) {
        s = fmaf(fmaf(ax, t, bx), t, cx) * t; // sampleCurveX (Horner’s scheme)
        if (x <= s) {
            t1 = t;
            t -= (s - x) / (s - t0) * dt;
            goto cont;
        }
        t0 = s;
    }
    t = 1 - (1 - x) / (1 - t0) * dt; // x > s, do last sample (s = ax + bx + cx = 1 when t = 1)
    cont:
    t0 = t1 - dt;
    // a few iterations of Newton-Raphson method
    #define kMaxNewtonIterations 4
    const float kBezierEpsilon = 1e-7f;
    const float newtonEpsilon = fminf(kBezierEpsilon, epsilon);
    for (i = 0; i < kMaxNewtonIterations; i++) {
        s = fmaf(fmaf(fmaf(ax, t, bx), t, cx), t, -x); // sampleCurveX - x
        if (fabsf(s) < newtonEpsilon) goto end;
        d = fmaf(ax * 3 * t + bx + bx, t, cx); // sampleCurveDerivativeX
        if (fabsf(d) < kBezierEpsilon) break;
        t -= s / d;
    }
    if (fabsf(s) < epsilon) goto end;
    // fall back to bisection method for reliability
    while (t0 < t1) {
        s = fmaf(fmaf(ax, t, bx), t, cx) * t; // sampleCurveX
        if (fabsf(s - x) < epsilon) goto end;
        if (x > s) t0 = t; else t1 = t;
        t = (t1 + t0) / 2;
    }
    // failure
    end:
    return fmaf(fmaf(ay, t, by), t, cy) * t; // sampleCurveY
}

// TODO: maybe add WebKit SpringSolver too ?
// https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/graphics/SpringSolver.h
