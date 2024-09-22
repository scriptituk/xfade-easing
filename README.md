# Easing and extensions for FFmpeg Xfade filter

### Standard easings &bull; CSS easings &bull; transpiled GLSL transitions &bull; custom expressions 

## Summary

This project is a port of standard easing equations, CSS easings and many [GLSL transitions](#glsl-transitions) for use in tandem with easing or alone.
The easing expressions can be used for other filters besides xfade.

<img src="assets/xfade-easing.gif" alt="Summary" align="right">

There are 2 variants:
1. **custom ffmpeg** build with xfade `easing` and `reverse` options
2. **custom expressions** for use with standard ffmpeg build

Xfade is a FFmpeg video transition filter with many built-in transitions and an expression evaluator for custom transitions.
However the progress rate is linear, starting and stopping abruptly and proceeding at constant speed,
therefore transitions lack interest.
Easing inserts a progress envelope to smooth transitions in a natural way.

Example usage:
* **custom ffmpeg**:
set the new `easing` option to the easing name, with optional CSS-easing arguments,
and the `transition` option to the transition name, with optional customisation arguments.  
*Example* (quartic-out,radial):  
`xfade=duration=3:offset=10:easing=quartic-out:transition=radial`  
*Example* (CSS,GL,reversed):  
`xfade=duration=3:offset=10:easing='cubic-bezier(0.12,0.57,0.63,0.21)'`  
`:transition='gl_cube(floating=5,unzoom=0.8)':reverse=1`  
* **custom expression**:
set the xfade `transition` option to `custom` and the `expr` option to the concatenation of a standard easing expression and a transition expression
(this variant does not support CSS easings).  
*Example* (quartic-out,radial):  
`xfade=duration=3:offset=10:transition=custom:expr='st(0,P^4);`  
`st(1,atan2(X-W/2,Y-H/2)-(ld(0)-0.5)*PI*2.5);st(1,st(1,clip(ld(1),0,1))*ld(1)*(3-2*ld(1)));B*ld(1)+A*(1-ld(1))'`  
Pre-generated [expressions](expr) can be copied verbatim from supplied files.

A [CLI wrapper script](#cli-script) is provided to generate custom expressions, test videos, visual media sequences and more.
It also facilitates generic ffmpeg filter easing – see [Easing other filters](#easing-other-filters).

The **custom ffmpeg** variant is fast with a simple API and no restrictions.
Installation involves a [few patches](https://htmlpreview.github.io/?https://github.com/scriptituk/xfade-easing/blob/main/src/vf_xfade-diff.html) to a single ffmpeg C source file, with no dependencies.
The **custom expression** variant is convenient but clunky
– see [Performance](#custom-expression-performance) –
and runs on plain vanilla ffmpeg but with restrictions:
it doesn’t support CSS easings, certain transitions, or the [reverse](#reversing-xfade-effects) feature.

At present extended transitions are limited to ported GLSL transitions but more effects may be added downstream.

---

## Example

### wipedown with cubic easing

![wipedown cubic](assets/wipedown-cubic.gif)

### CLI command (for custom ffmpeg use)

```bash
ffmpeg -i first.mp4 -i second.mp4 -filter_complex "
    xfade=duration=3:offset=1:easing=cubic-in-out:transition=wipedown
    " output.mp4
```
Easing mode `in-out` is the default mode; the above is equivalent to `easing=cubic`.  
The default easing is `linear` (none).

### CLI command (for custom expression use)

```bash
ffmpeg -i first.mp4 -i second.mp4 -filter_complex_threads 1 -filter_complex "
    xfade=duration=3:offset=1:transition=custom:expr='
        st(0, if(lt(P, 0.5), 4 * P^3, 1 - 4 * (1-P)^3)) ;
        if(gt(Y, H*(1-ld(0))), A, B)
    '" output.mp4
```

Here, the `expr` parameter is shown on two lines for clarity.  
The first line is the easing expression $e(P)$ (`cubic in-out`) which stores its calculated progress value in `st(0)`.  
The second line is the  transition expression $t(e(P))$ (`wipedown`) which loads its eased progress value from `ld(0)` instead of `P`.
The semicolon token combines expressions.

> [!CAUTION]
> ffmpeg option `-filter_complex_threads 1` is required because xfade expression variables (the `st()` & `ld()` functions) are shared between slice processing jobs and therefore not thread-safe, consequently processing is much slower

### Getting the expressions

In this example you can copy the easing expression from file [easings-inline.txt](expr/easings-inline.txt) and the transition expression from [transitions-rgb24-inline.txt](expr/transitions-rgb24-inline.txt) or [transitions-yuv420p-inline.txt](expr/transitions-yuv420p-inline.txt).
Those contain inline expressions for CLI use.

Alternatively use the [CLI script](#cli-script):
```bash
xfade-easing.sh -t wipedown -e cubic -x -
```
dumps the xfade `expr` parameter:
```
'st(0,if(lt(P,0.5),4*P^3,1-4*(1-P)^3));if(gt(Y,H*(1-ld(0))),A,B)'
```

### Using a script

Some expressions are very long, so using a filtergraph script keeps things manageable and readable.

For this same example you can copy the easing expression from file [easings-script.txt](expr/easings-script.txt) and the transition expression from [transitions-rgb24-script.txt](expr/transitions-rgb24-script.txt) or [transitions-yuv420p-script.txt](expr/transitions-yuv420p-script.txt).
Those contain multiline expressions for script use (but the inline expressions work too).

Alternatively use [xfade-easing.sh](#cli-script) with expansion specifiers `expr='%n%X'` (see [Usage](#usage)):
```bash
xfade-easing.sh -t wipedown -e cubic -s "xfade=offset=10:duration=5:transition=custom:expr='%n%X'" -x script.txt
```
writes the complete xfade filter description to file script.txt:
```
xfade=offset=10:duration=5:transition=custom:expr='
st(0, if(lt(P, 0.5), 4 * P^3, 1 - 4 * (1-P)^3))
;
if(gt(Y, H * (1 - ld(0))), A, B)'
```
and the command becomes
```bash
ffmpeg -i first.mp4 -i second.mp4 -filter_complex_threads 1 -/filter_complex script.txt output.mp4`
```

> [!NOTE]
> this option syntax has changed and is not documented:
> - for ffmpeg version 7+ use `-/filter_complex filename`
> - for earlier versions use `-filter_complex_script filename`

---

## Custom FFmpeg

### Building ffmpeg

This is easy:

1. check the [FFmpeg Compilation Guide](https://trac.ffmpeg.org/wiki/CompilationGuide) for any prerequisites, e.g. macOS requires Xcode
1. get the ffmpeg source tree:  
use latest stable release at [Download Source Code](https://ffmpeg.org/download.html) then extract the .xz archive:  
`tar -xJf ffmpeg-x.x.x.tar.xz` or use `xz`/`gunzip`/etc.
1. `cd ffmpeg` and patch libavfilter/vf_xfade.c:
   - download [vf_xfade.patch](src/vf_xfade.patch) and run `git apply vf_xfade.patch`
   - or download [patched vf_xfade.c](src/vf_xfade.c) (for ffmpeg v7.0.2)
   - or patch manually, see [vf_xfade diff](https://htmlpreview.github.io/?https://github.com/scriptituk/xfade-easing/blob/main/src/vf_xfade-diff.html) – only 9 small changes  
1. download [xfade-easing.h](src/xfade-easing.h) to libavfilter/
1. run `./configure` with any `--prefix` and other options (drawtext requires `--enable-libfreetype` `--enable-libharfbuzz` `--enable-libfontconfig`);
   to replicate an existing configuration run `ffmpeg -hide_banner -buildconf` and copy-paste the options
1. run `make`, it takes a while  
the C99 code mixes declarations and statements so may produce profuse compiler warnings  
the fix for `ld: warning: text-based stub file are out of sync` warnings [is here](https://stackoverflow.com/questions/51314888/ld-warning-text-based-stub-file-are-out-of-sync-falling-back-to-library-file)
1. if required run `make install` or use ffmpeg from the root source directory
1. test using `ffmpeg -hide_banner --help filter=xfade`: there should be `easing` and `reverse` options under `xfade AVOptions`

For simplicity, xfade-easing is implemented as static functions in the header file [xfade-easing.h](src/xfade-easing.h) and included into vf_xfade.c at an optimal place.
As those functions have no external linkage and completely implement an interface that is only visible to the vf_xfade.c compilation unit, this approach is justified IMO, even if unusual, and obviates changing the Makefile. Implementation within header files is not uncommon.

### Testing

The custom FFmpeg version has been built and tested on Mac with Clang and Ubuntu Linux with GCC, not Windows.
It uses C99 features so expect some warnings.

---

## Custom expressions

Pre-generated easing and transition expressions are in the [expr/](expr) subdirectory for mix and match use.
The [CLI script](#cli-script) can produce combined expressions in any syntax using expansion specifiers (like `printf`).

### Inline, for -filter_complex

This format is condensed into a single line stripped of whitespace.

*Example*: `elastic out` easing (leaves progress in `st(0)`)
```
st(0,cos(20*(1-P)*PI/3)/2^(10*(1-P)))
```

### Script, for -/filter_complex

This format is best for expressions that are too unwieldy for inline ffmpeg commands.

*Example*: `gl_rotate_scale_fade` transition (expects progress in `ld(0)` (cf. [rotate_scale_fade.glsl](https://github.com/gl-transitions/gl-transitions/blob/master/transitions/rotate_scale_fade.glsl))
```
st(1, 0.5);
st(2, 0.5);
st(3, 1);
st(4, 8);
st(5, X / W - ld(1));
st(6, 1 - Y / H - ld(2));
st(7, hypot(ld(5), ld(6)));
st(5, ld(5) / ld(7));
st(6, ld(6) / ld(7));
st(3, 2 * PI * ld(3) * (1 - ld(0)));
st(8, 2 * abs(ld(0) - 0.5));
st(8, ld(4) * (1 - ld(8)) + 1 * ld(8));
st(4, ld(5) * cos(ld(3)) - ld(6) * sin(ld(3)));
st(6, ld(5) * sin(ld(3)) + ld(6) * cos(ld(3)));
st(1, ld(1) + ld(4) * ld(7) / ld(8));
st(2, ld(2) + ld(6) * ld(7) / ld(8));
if(between(ld(1), 0, 1) * between(ld(2), 0, 1),
 st(1, ld(1) * W);
 st(2, (1 - ld(2)) * H);
 st(3, ifnot(PLANE, a0(ld(1),ld(2)), if(eq(PLANE,1), a1(ld(1),ld(2)), if(eq(PLANE,2), a2(ld(1),ld(2)), a3(ld(1),ld(2))))));
 st(4, ifnot(PLANE, b0(ld(1),ld(2)), if(eq(PLANE,1), b1(ld(1),ld(2)), if(eq(PLANE,2), b2(ld(1),ld(2)), b3(ld(1),ld(2))))));
 st(5, 1 - ld(0));
 ld(3) * (1 - ld(5)) + ld(4) * ld(5),
 st(1, 0.15);
 if(eq(PLANE,3), 255, ld(1)*255)
)
```

### Uneased, for transitions without easing

These use `P` directly for progress instead of `ld(0)`. They are especially useful for non-xfade transitions where custom expressions are always needed.

*Example*: `gl_WaterDrop` transition (cf. [WaterDrop.glsl](https://github.com/gl-transitions/gl-transitions/blob/master/transitions/WaterDrop.glsl))

```
st(1, 30);
st(2, 30);
st(3, 1 - P);
st(4, X / W - 0.5);
st(5, 0.5 - Y / H);
st(6, hypot(ld(4), ld(5)));
st(7, if(lte(ld(6), ld(3)),
 st(1, sin(ld(6) * ld(1) - ld(3) * ld(2)));
 st(4, ld(4) * ld(1));
 st(5, ld(5) * ld(1));
 st(4, X + ld(4) * W);
 st(5, Y - ld(5) * H);
 ifnot(PLANE, a0(ld(4),ld(5)), if(eq(PLANE,1), a1(ld(4),ld(5)), if(eq(PLANE,2), a2(ld(4),ld(5)), a3(ld(4),ld(5))))),
 A
));
ld(7) * (1 - ld(3)) + B * ld(3)
```

### Generic, for easing other filters

These ease `ld(0)` instead od `P` - see [Easing other filters](#easing-other-filters).

---

## Easing

### Standard easings (Robert Penner)

This implementation derives from [Michael Pohoreski’s](https://github.com/Michaelangel007/easing#tldr-shut-up-and-show-me-the-code) single argument version of [Robert Penner’s](http://robertpenner.com/easing/) easing functions, further optimised by me for the peculiarities of xfade.

- `quadratic`
- `cubic`
- `quartic`
- `quintic`
- `sinusoidal`
- `exponential`
- `circular`
- `elastic`
- `back`
- `bounce`

![standard easings](assets/standard-easings.png)

### Supplementary easings

- `squareroot`
- `cuberoot`

The `squareroot` and `cuberoot` easings focus more on the middle regions and less on the extremes, opposite to `quadratic` and `cubic` respectively:

![supplementary easings](assets/supplementary-easings.png)

### All standard and supplementary easings

Here are all the above easings superimposed using the [Desmos Graphing Calculator](https://www.desmos.com/calculator):

![all easings](assets/all-easings.png)

### CSS easings

The custom ffmpeg variant supports [CSS Easing Functions Level 2](https://drafts.csswg.org/css-easing-2/) which are too complex for custom expressions:

- `linear` `linear()`
- `ease` `ease-in` `ease-out` `ease-in-out` `cubic-bezier()`
- `step-start` `step-end` `steps()`

#### Linear easing

The new CSS `linear()` function can approximate any progress contour by interpolating between adjacent points,
documented at [W3C here](https://drafts.csswg.org/css-easing-2/#the-linear-easing-function).
There’s a [CSS Linear() Generator](https://linear-easing-generator.netlify.app/) online by its pioneer Jake Archibald to convert easings expressed in JavaScript or SVG to `linear()`.

![linear easing](assets/css-linear.gif)

#### Cubic Bézier easing

There are 4 fixed CSS smoothing curves and a general `cubic-bezier()` easing function
documented at [W3C here](https://drafts.csswg.org/css-easing-2/#cubic-bezier-easing-functions).
See also the [CSS Cubic Bezier Generator](https://www.cssportal.com/css-cubic-bezier-generator/) to craft your own.
The implementation used here is transpiled from Apple’s [open-source Webkit](https://github.com/WebKit/WebKit).

![cubic-bezier easing](assets/css-cubic-bezier.gif)

#### Step easing

The CSS `steps()` staircase function is for transitions that jump a constant amount,
documented at [W3C here](https://drafts.csswg.org/css-easing-2/#step-easing-functions).

![step easing](assets/css-steps.gif)

#### Reversed CSS easing

Standard easings have ease-in and ease-out modes but not CSS easings.
See [Reversing xfade effects](#reversing-xfade-effects) to achieve this with the custom ffmpeg build.

### Overshoots

The `elastic` and `back` easings overshoot and undershoot, causing many transitions to clip and others to show colour distortion.
Therefore they are quite useless for xfade (but see [Easing other filters](#easing-other-filters)).
CSS easings `linear()` and `cubic-bezier()` can also overshoot.

Rendering expressions can only access the two frames of data available.
A wrapping overshoot strategy might work for simple horizontal/vertical effects whereby fetching X & Y pixel data is intercepted
but at present eased progress outside the range 0 to 1 yields unpredictable results.

### Easing other filters

The easing expressions are useful for filters other than xfade,
e.g. blend, drawtext, geq, overlay, rotate, zoompan, etc.
– anywhere an ffmpeg expr is used to calculate filter options.

For this purpose the [CLI script](#cli-script) includes text expansion codes `%g` & `%G` to generate generic easing expressions for the value in `ld(0)` (instead of `P` for xfade), leaving the result in `ld(0)`.
You can also copy generic easing expressions from file [generic-easings-inline.txt](expr/generic-easings-inline.txt) for inline `-filter_complex` use, or [generic-easings-script.txt](expr/generic-easings-script.txt) for `-/filter_complex` scripts.

To ease other filters, store a normalised input value in `st(0,…)`, append the easing expression, then scale the eased result left in `ld(0)`.

*Example*: zoompan filter with `elastic-out` zooming

![zoompan elastic-out easing](assets/zoompan.gif)

Here’s the `zoom` option expression for the zoompan filter:
```
zoom='st(0, clip((time - 1) / 3, 0, 1));
        st(0, 1 - cos(20 * ld(0) * PI / 3) / 2^(10 * ld(0)));
      lerp(1, 3, ld(0))'
```
The first line stores a 3 second duration delayed by 1 second normalised to a value between 0 and 1.  
The last line scales the result to zoom between 1x and 3x.  
The middle line performs `elastic-out` easing, obtained from [generic-easings-script.txt](expr/generic-easings-script.txt), or  
`xfade-easing.sh -e elastic-out -s %G -x -`

The [zoompan filter](https://ffmpeg.org/ffmpeg-filters.html#zoompan) can produce impressive [Ken Burns effects](https://www.epidemicsound.com/blog/ken-burns-effect/) when `zoom`, `x` & `y` are all dynamic.
Adding easing can take the illusion of motion even further.
I have another FFmpeg project on the go that does just that.

*Example*: zoompan with `back` zooming and drawtext with `squareroot` scrolling

![zoompan back + drawtext squareroot easing](assets/zoompan-drawtext.gif)

The initial zoom here is 1.2x to accommodate the 10% undershoot that `back` easing produces.
So the zoompan `zoom` expression, with `back` expr from [generic-easings-inline.txt](expr/generic-easings-inline.txt), is:
```
z='st(0, clip((time - 1) / 3, 0, 1));
     st(0,if(lt(ld(0),0.5),2*ld(0)*ld(0)*(2*ld(0)*3.59491-2.59491),1-2*(1-ld(0))^2*(4.59491-2*ld(0)*3.59491)));
   lerp(1.2, 3.1, ld(0))'
```
And the drawtext `y` expression with `squareroot` easing is:
```
y='st(0, clip((t - 1) / 3, 0, 1));
     st(0, if(lt(ld(0), 0.5), sqrt(2 * ld(0)), 2 - sqrt(2 * (1 - ld(0)))) / 2);
   lerp(line_h + 3, h - line_h * 2 + 5, ld(0))'
```

---

## Transitions

### Xfade transitions

The custom ffmpeg variant eases the built-in xfade transitions; these are provided for custom expression use.
They are converted from C-code in [vf_xfade.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_xfade.c) to custom expressions for use with easing.
Omitted transitions are `distance` and `hblur` which perform aggregation, so cannot be computed efficiently on a per plane-pixel basis.

- `fade` `fadefast` `fadeslow`
- `fadeblack` `fadewhite` `fadegrays`
- `wipeleft` `wiperight` `wipeup` `wipedown`
- `wipetl` `wipetr` `wipebl` `wipebr`
- `slideleft` `slideright` `slideup` `slidedown`
- `smoothleft` `smoothright` `smoothup` `smoothdown`
- `circlecrop` `rectcrop`
- `circleopen` `circleclose`
- `vertopen` `vertclose` `horzopen` `horzclose`
- `diagtl` `diagtr` `diagbl` `diagbr`
- `hlslice` `hrslice` `vuslice` `vdslice`
- `radial` `zoomin`
- `dissolve` `pixelize`
- `squeezeh` `squeezev`
- `hlwind` `hrwind` `vuwind` `vdwind`
- `coverleft` `coverright` `coverup` `coverdown`
- `revealleft` `revealright` `revealup` `revealdown`

#### Gallery

Here are the xfade transitions processed using custom expressions instead of the built-in transitions (for testing), without easing –
see also the FFmpeg [Wiki Xfade](https://trac.ffmpeg.org/wiki/Xfade#Gallery) page:

![Xfade gallery](assets/xf-gallery.gif)

### GLSL transitions

The open collection of [GL Transitions](https://gl-transitions.com/) initiative lead by [Gaëtan Renaudeau](https://github.com/gre) (gre)
“aims to establish an universal collection of transitions that various softwares can use” released under a Free License.

Other GLSL transition sources were found on [shadertoy](https://www.shadertoy.com/) and the [Vegas Forum](https://www.vegascreativesoftware.info/us/forum/gl-transitions-gallery-sharing-place-share-the-code-here--133472/).
All GLSL transitions adapted to the GL Transition Specification are at [glsl/](glsl/).

Many of the transitions at [gl-transitions](https://github.com/gl-transitions/gl-transitions/tree/master/transitions) and elsewhere
have been transpiled to native C transitions (for custom ffmpeg variant) and custom expressions (for custom expression variant) for use with or without easing.
The list shows the names, authors, and customisation parameters and defaults:

- `gl_angular` [args: `startingAngle`,`clockwise`; default: `(90,0)`] (by: Fernando Kuteken)
- `gl_BookFlip` (by: hong)
- `gl_Bounce` [args: `shadowAlpha`,`shadowHeight`,`bounces`,`direction`; default: `(0.6,0.075,3,0)`] (by: Adrian Purser)
- `gl_BowTie` [args: `vertical`; default: `(0)`] (by: huynx)
- `gl_cannabisleaf` (by: Flexi23)
- `gl_CornerVanish` (by: Mark Craig)
- `gl_CrazyParametricFun` [args: `a`,`b`,`amplitude`,`smoothness`; default: `(4,1,120,0.1)`] (by: mandubian)
- `gl_crosshatch` [args: `center.x`,`center.y`,`threshold`,`fadeEdge`; default: `(0.5,0.5,3,0.1)`] (by: pthrasher)
- `gl_CrossOut` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_crosswarp` (by: Eke Péter)
- `gl_cube` [args: `persp`,`unzoom`,`reflection`,`floating`,`bgBkWhTr`; default: `(0.7,0.3,0.4,3,0)`] (by: gre)
- `gl_Diamond` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_DirectionalScaled` [args: `direction.x`,`direction.y`,`scale`,`bgBkWhTr`; default: `(0,1,0.7,0)`] (by: Thibaut Foussard)
- `gl_directionalwarp` [args: `smoothness`,`direction.x`,`direction.y`; default: `(0.1,-1,1)`] (by: pschroen)
- `gl_doorway` [args: `reflection`,`perspective`,`depth`,`bgBkWhTr`; default: `(0.4,0.4,3,0)`] (by: gre)
- `gl_DoubleDiamond` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_Dreamy` (by: mikolalysenko)
- `gl_Exponential_Swish` [args: `zoom`,`angle`,`offset`,`exponent`,`wrap.x`,`wrap.y`,`blur`,`bgBkWhTr`; default: `(0.8,0,0,4,2,2,0,0)`] (by: Boundless)
- `gl_FanIn` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_FanOut` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_FanUp` [args: `smoothness`; default: `(0.05)`] (by: Mark Craig)
- `gl_Flower` [args: `smoothness`,`rotation`; default: `(0.05,360)`] (by: Mark Craig)
- `gl_GridFlip` [args: `size.x`,`size.y`,`pause`,`dividerWidth`,`randomness`,`bgBkWhTr`; default: `(4,4,0.1,0.05,0.1,0)`] (by: TimDonselaar)
- `gl_heart` (by: gre)
- `gl_hexagonalize` [args: `steps`,`horizontalHexagons`; default: `(50,20)`] (by: Fernando Kuteken)
- `gl_InvertedPageCurl` [args: `angle`,`radius`,`reverseEffect`; default: `(100,0.159,0)`] (by: Hewlett-Packard)
- `gl_kaleidoscope` [args: `speed`,`angle`,`power`; default: `(1,1,1.5)`] (by: nwoeanhinnogaehr)
- `gl_Lissajous_Tiles` [args: `grid.x`,`grid.y`,`speed`,`freq.x`,`freq.y`,`offset`,`zoom`,`fade`,`backColor`; default: `(10,10,0.5,2,3,2,0.8,3,0)`] (by: Boundless)
- `gl_Mosaic` [args: `endx`,`endy`; default: `(2,-1)`] (by: Xaychru)
- `gl_perlin` [args: `scale`,`smoothness`; default: `(4,0.01)`] (by: Rich Harris)
- `gl_pinwheel` [args: `speed`; default: `(2)`] (by: Mr Speaker)
- `gl_polar_function` [args: `segments`; default: `(5)`] (by: Fernando Kuteken)
- `gl_PolkaDotsCurtain` [args: `dots`,`centre.x`,`centre.y`; default: `(20,0,0)`] (by: bobylito)
- `gl_powerKaleido` [args: `scale`,`z`,`speed`; default: `(2,1.5,5)`] (by: Boundless)
- `gl_randomNoisex` (by: towrabbit)
- `gl_randomsquares` [args: `size.x`,`size.y`,`smoothness`; default: `(10,10,0.5)`] (by: gre)
- `gl_ripple` [args: `amplitude`,`speed`; default: `(100,50)`] (by: gre)
- `gl_Rolls` [args: `type`,`rotDown`; default: `(0,0)`] (by: Mark Craig)
- `gl_RotateScaleVanish` [args: `fadeInSecond`,`reverseEffect`,`reverseRotation`,`bgBkWhTr`; default: `(1,0,0,0)`] (by: Mark Craig)
- `gl_rotateTransition` (by: haiyoucuv)
- `gl_rotate_scale_fade` [args: `centre.x`,`centre.y`,`rotations`,`scale`,`backColor`; default: `(0.5,0.5,1,8,0.15)`] (by: Fernando Kuteken)
- `gl_SimpleBookCurl` [args: `angle`,`radius`,`shadow`; default: `(150,0.1,0.2)`] (by: Raymond Luckhurst)
- `gl_SimplePageCurl` [args: `angle`,`radius`,`roll`,`reverseEffect`,`greyBack`,`opacity`,`shadow`; default: `(80,0.15,0,0,0,0.8,0.2)`] (by: Andrew Hung)
- `gl_Slides` [args: `type`,`slideIn`; default: `(0,0)`] (by: Mark Craig)
- `gl_squareswire` [args: `squares.h`,`squares.v`,`direction.x`,`direction.y`,`smoothness`; default: `(10,10,1.0,-0.5,1.6)`] (by: gre)
- `gl_StarWipe` [args: `border_thickness`,`star_rotation`,`border_color`; default: `(0.01,0.75,1)`] (by: Ben Lucas)
- `gl_static_wipe` [args: `upToDown`,`maxSpan`; default: `(1,0.5)`] (by: Ben Lucas)
- `gl_Stripe_Wipe` [args: `nlayers`,`layerSpread`,`color1`,`color2`,`shadowIntensity`,`shadowSpread`,`angle`; default: `(3,0.5,0x3319CCFF,0x66CCFFFF,0.7,0,0)`] (by: Boundless)
- `gl_swap` [args: `reflection`,`perspective`,`depth`,`bgBkWhTr`; default: `(0.4,0.2,3,0)`] (by: gre)
- `gl_Swirl` (by: Sergey Kosarevsky)
- `gl_WaterDrop` [args: `amplitude`,`speed`; default: `(30,30)`] (by: Paweł Płóciennik)
- `gl_windowblinds` (by: Fabien Benetou)
#### Gallery

<!-- GL pics at https://github.com/gre/gl-transition-libs/tree/master/packages/website/src/images/raw -->

Here are the ported GLSL transitions with default parameters and no easing.
See also the [GL Transitions Gallery](https://gl-transitions.com/gallery)
which lacks many recent contributor transitions plus even more stacking up as
[Pull requests](https://github.com/gl-transitions/gl-transitions/pulls) –
which is why I have not added my bundle.

![GL gallery](assets/gl-gallery.gif)

#### With easing

GLSL transitions can also be eased, although easing is integral with some:

*Example*: `Swirl` transition with `bounce` easing

![Swirl bounce](assets/gl_Swirl-bounce.gif)

#### Customisation parameters

Many GLSL transitions accept parameters to customise the transition effect.
The parameters and default values are shown [above](#glsl-transitions).

*Example*: two pinwheel speeds: `'gl_pinwheel(0.5)'` and `'gl_pinwheel(10)'`

![gl_pinwheel(10)](assets/gl_pinwheel_10.gif)

Parameters are appended to the transition name as CSVs within parenthesis.

For the custom ffmpeg variant the parameters may be name=value pairs in any order,
e.g. `gl_WaterDrop(speed=20,amplitude=50)`,
or they may be indexed values, as follows.

For the custom expression variant the parameters must be indexed values only but empty values assume defaults,
e.g. `gl_GridFlip(5,3,,0.1,,1)` arguments are `size.x=5`,`size.y=3`,`dividerWidth=0.1`,`bgBkWhTr=1` with default values for other parameters.

Custom [expressions](expr) can also be amended directly:
parameters are specified using store functions `st(p,v)`
where `p` is the parameter number and `v` its value.
So for `gl_pinwheel` with a `speed` value 10, change the first line of its expr below to `st(1, 10);`.
```
st(1, 2);
st(2, 1 - ld(0));
st(1, atan2(0.5 - Y / H, X / W - 0.5) + ld(2) * ld(1));
st(1, mod(ld(1), PI / 4));
if(lte(ld(2), ld(1)), A, B)
```
Similarly, `gl_directionalwarp` takes 3 parameters: `smoothness`, `direction.x`, `direction.y` (from `xfade-easing.sh -L`)
and its expr starts with 3 corresponding `st()` (store) functions which may be changed from their default values:
```
st(1, 0.1);
st(2, -1);
st(3, 1);
st(4, hypot(ld(2), ld(3)));
etc.
```

#### Altered GL Transitions

- `gl_angular` has an additional `clockwise` parameter
- `gl_Bounce` has an additional `direction` parameter to control bounce direction:
`0`=south, `1`=west, `2`=north, `3`=east
- `gl_BowTie` combines `BowTieHorizontal` and `BowTieVertical` using parameter `vertical`
- `gl_Exponential_Swish` option `blur` default was originally `0.5` but blurring makes it unacceptably slow
- `gl_InvertedPageCurl` omits anti-aliased edges and takes 3 parameters:
  - `angle` may be `100` (default) or `30` degrees from horizontal east
  - `radius` is the cylinder radius
  - `reverseEffect` produces an uncurl effect (custom ffmpeg only)
- `gl_RotateScaleVanish` has an additional `trkMat` parameter (track matte, custom ffmpeg only) which treats the moving image/video as a variable-transparency overlay – see Dr Who example under [Transparency](#transparency)
(I might add this feature to other transitions)
- `gl_rotate_scale_fade` option `backColor` is restricted to greyscale for the custom expression variant
- several GL Transitions show a black background during their transition, e.g. `gl_cube` and `gl_doorway`,
but this implementation provides an additional `bgBkWhTr` parameter to control the background:
`0`=black (default), `1`=white, `-1`=transparent

*Example*: `gl_InvertedPageCurl` 30° with uncurl
(useful for sheet music with repeats)  
`'gl_InvertedPageCurl(30,0.15,0)'` and `'gl_InvertedPageCurl(30,0.15,1)'` concatenated

![gl_InvertedPageCurl(30)](assets/flipchart.gif)

#### Porting

GLSL shader code runs on the GPU in real time. However GL Transition and Xfade APIs are broadly similar and non-complex algorithms are easily ported using vector resolution.

| context | GL Transitions | Xfade filter | notes |
| :---: | :---: | :---: | --- |
| progress | `uniform float progress` <br/> moves from 0&nbsp;to&nbsp;1 | `P` <br/> moves from 1 to 0 | `progress ≡ 1 - P` |
| ratio | `uniform float ratio` | `W / H` | GL width and height are normalised |
| coordinates | `vec2 uv` <br/> `uv.y == 0` is bottom <br/> `uv == vec2(1.0)` is top-right | `X`, `Y` <br/> `Y == 0` is top <br/> `(X,Y) == (W,H)` is bottom-right | `uv.x ≡ X / W` <br/> `uv.y ≡ 1 - Y / H` |
| texture | `vec4 getFromColor(vec2 uv)` <hr/> `vec4 getToColor(vec2 uv)` | `a0(x,y)` to `a3(x,y)` <br/> or `A` for first input <hr/> `b0(x,y)` to `b3(x,y)` <br/> or `B` for second input | `vec4 transition(vec2 uv) {...}` runs for every pixel position <br/> xfade `expr` is evaluated for every texture component (plane) and pixel position |
| plane data | normalised RGBA | GBRA or YUVA unsigned integer | xfade bit depth depends on pixel format |

To make the transpiled code easier to follow,
original variable names from the GLSL and xfade source code are replicated in
[xfade-easing.sh](src/xfade-easing.sh) and [xfade-easing.h](src/xfade-easing.h).
The script uses pseudo functions to emulate real functions, expanding them inline later.

*Example*: porting transition `gl_randomsquares`

[randomsquares.glsl](https://github.com/gl-transitions/gl-transitions/blob/master/transitions/randomsquares.glsl):

```glsl
uniform ivec2 size; // = ivec2(10, 10)
uniform float smoothness; // = 0.5

float rand (vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec4 transition(vec2 p) {
    float r = rand(floor(vec2(size) * p));
    float m = smoothstep(0.0, -smoothness, r - (progress * (1.0 + smoothness)));
    return mix(getFromColor(p), getToColor(p), m);
}
```

[xfade-easing.sh](src/xfade-easing.sh) (custom expression variant):
```bash
gl_randomsquares) # (case)
    _make "st(1, ${a[0]-10});" # size.x
    _make "st(2, ${a[1]-10});" # size.y
    _make "st(3, ${a[2]-0.5});" # smoothness
    _make 'st(1, floor(ld(1) * X / W));'
    _make 'st(2, floor(ld(2) * (1 - Y / H)));'
    _make 'st(4, frand(ld(1), ld(2), 4));' # r
    _make 'st(4, ld(4) - ((1 - P) * (1 + ld(3))));'
    _make 'st(4, smoothstep(0, -ld(3), ld(4), 4));' # m
    _make 'mix(A, B, ld(4))'
    ;;
```
Here, `frand()`, `smoothstep()` and `mix()` are pseudo functions.
Customizable parameters are generally stored first.
`_make` is just an expression string builder function.

[xfade-easing.h](src/xfade-easing.h) (custom ffmpeg variant):
```c
static vec4 gl_randomsquares(const XTransition *e)
{
    PARAM_BEGIN
    PARAM_2(ivec2, size, 10, 10)
    PARAM_1(float, smoothness, 0.5)
    PARAM_END
    float r = frand2(floor2(mul2(vec2i(size), e->p)));
    float m = smoothstep(0, -smoothness, r - e->progress * (1 + smoothness));
    return mix4(e->a, e->b, m);
}
```
Here, `vec4` and `ivec2` simulate GLSL vector types and `XTransition` encapsulates all data pertaining to a transition:
```c
typedef struct { // modelled on GL Transition Specification v1
    const float progress; // transition progress, moves from 0.0 to 1.0 (cf. P)
    const float ratio; // viewport width / height (cf. W / H)
    vec2 p; // pixel position in slice, .y==0 is bottom (cf. X, Y)
    vec4 a, b; // plane data at p (cf. A, B)
    ...
} XTransition;
```

### Curls and Rolls

##### Transition `gl_InvertedPageCurl`

This is transpiled from the
[InvertedPageCurl](https://github.com/gl-transitions/gl-transitions/blob/master/transitions/InvertedPageCurl.glsl)
GL transition which originated from the
[WebVfx WebGL pagecurl shader](https://webvfx.rectalogic.com/examples_2transition-shader-pagecurl_8html-example.html)
which is itself based on code by [Calyptus Life AB](http://blog.calyptus.eu/) which seems no longer available.
The Hewlett-Packard accreditation by Sergey Kosarevsky is obscure but preserved here.

##### Transition `gl_SimplePageCurl`

This is adapted from the elegant
[simple page curl effect ](https://www.shadertoy.com/view/ls3cDB) by Andrew Hung
who also provides an excellent [shader breakdown](https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/)
to demystify the deformation effect.  
It is more versatile than `gl_InvertedPageCurl` and takes the following parameters:
- `angle` may be any 360° angle
  (horizontal east is 0°, curl direction is `angle - 90°` anticlockwise);
  in effect, 1–89° curls from bottom-right; 91–179° top-right; 181–269° (or -91–-179°) top-left; 271–359° (or -1–-89°) bottom-left;
  0° curls upwards; 90° left; ±180° down; 270° (or -90°) right
- `radius` sets the cylinder radius
- `roll` to roll the turning page into a cylinder (`gl_InvertedPageCurl` only rolls)
- `reverseEffect` to uncurl or unroll
- `greyBack` to render overleaf greyscale instead of colour
- `opacity` the underside opacity
- `shadow` the shadow intensity

The main differences from `gl_InvertedPageCurl` are:
- curling in any direction, not just right-to-left at 30° or 100°
- takes aspect ratio into account, ensuring accurate angle
- can render back of turning page either rolling or just curled over
- back of turning page rendered in colour or greyscale with variable opacity
- smaller default radius of 0.15, not 1/2π

*Example*: using `gl_SimplePageCurl` to emulate `gl_InvertedPageCurl`  
`'gl_InvertedPageCurl(30)'` vs `'gl_SimplePageCurl(24.8,0.159,1,0,1,0.8,0.1)'`  
these parameters factor in the disregarded aspect ratio (5:4 here), 1/2π radius, roll effect, greyscale overleaf, and shadowing.

![gl_PageCurl](assets/curl.gif)

There is barely any noticeable difference,
which confirms Mr Hung’s observation that complex mathematics is unjustified: scalar product projections and simple trigonometry are sufficient.

*Example*: `gl_SimplePageCurl` with various `angle` and `roll` options
(Abstract and Renaissance art by Kandinsky and Titian)

![gl_SimplePageCurl](assets/art.gif)

A by-product effect is a wipe transition in any direction, achieved by setting `radius=0`,`roll=1`.

*Example*: `'gl_SimplePageCurl(160,0,1)'` 160° wipe

![gl_SimplePageCurl-wipe](assets/wipe.gif)

##### Transition `gl_SimpleBookCurl`

(custom ffmpeg only)

This is adapted from `gl_SimplePageCurl` to clamp the curl to the virtual ‘spine’ at the horizontal centre,
then to flatten the radius to zero, using built-in easing to appear more realistic.  
It takes the following parameters:
- `angle` may be any 360° angle
  (horizontal east is 0°, curl direction is `angle - π/2` anticlockwise);
  in effect, angles from 180° to 359° (or -1° to -180°) page backwards
- `radius` sets the cylinder radius
- `shadow` the shadow intensity

*Example*: `gl_SimpleBookCurl` with various `angle` and `radius` values paging forwards and backwards, rotated and overlaid onto a desk texture
(credit: [Ethical Corporation Magazine](https://1.reutersevents.com/LP=36432))

![gl_SimpleBookCurl](assets/journal.gif)

### Pixel format

Transitions that affect colour components work differently for RGB than non-RGB colour spaces and for different bit depths.
For the custom expression variant, [xfade-easing.sh](#cli-script) emulates [vf_xfade.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_xfade.c) function `config_output()` logic, deducing the RGB signal type `AV_PIX_FMT_FLAG_RGB` from the `-f` option format name (rgb/bgr/etc. see [pixdesc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavutil/pixdesc.c)) and the bit depth from `ffmpeg -pix_fmts` data.
It can then set the black, white and mid plane values correctly.
See [How does FFmpeg identify color spaces?](https://trac.ffmpeg.org/wiki/colorspace#HowdoesFFmpegidentifycolorspaces) for details.

The expression files in [expr/](expr) cater for RGB and YUV formats with 8-bit component depth.
For faster processing of greyscale media use `xfade-easing.sh -f gray`.
Greyscale is not RGB therefore it is processed as a luma plane.

If in doubt, check with `ffmpeg -pix_fmts` or use the [xfade-easing.sh](#cli-script) `-f` option.

### Transparency

The expression files in [expr/](expr) also cater for RGBA and YUVA formats with 4 planes.

For lossless intermediate video content with alpha channel support use the [xfade-easing.sh](#cli-script) `-f -v ` options with an alpha format, e.g. `rgba`/`yuva420p`, and .mkv filename extension.
For lossy video with alpha use an alpha format and the .webm extension.

*Example*: overlaid transparent `gl_RotateScaleVanish` transition with `quadratic-in` easing
```bash
xfade-easing.sh -f rgba -e quadratic-in -t 'gl_RotateScaleVanish(FadeInSecond=0,ReverseEffect=1,trkMat=1)' -v alpha.mkv -z 250x skaro.png tardis.png
ffmpeg -i gallifrey.png -i alpha.mkv -filter_complex '[0]scale=250:-2[b]; [b][1]overlay' drwho.mp4
```

![alpha](assets/alpha.gif)

This demonstrates the additional `trkMat` option which tracks the Tardis alpha value to expose Skaro behind,
then Gallifrey’s Citadel when the transition ends, both planets being opaque images.  
(trkMat is only availble in the custom ffmpeg variant)

See also the example under [Transition `gl_SimpleBookCurl`](#transition-gl_simplebookcurl).

### Colour parameters

For the custom expression variant, which does not support colour,
values are specified as a decimal proportion of maximum and rendered as greyscale.  
e.g. `gl_rotate_scale_fade(backColor=0.75)`

For the custom ffmpeg variant,
decimal values from 0 to 1 are rendered as greyscale, as above,
but all other values are treated as RGBA colour, specified using the ffmpeg syntax at
[Color](https://ffmpeg.org/ffmpeg-utils.html#Color).  
e.g. `gl_Stripe_Wipe(color1=DeepSkyBlue,color2=ffd700)`  
Consequently. a value of exactly 1 is rendered white but 2 (RGB `#000002`) is nearly black.  
Colour examples:  
- `random` (a random colour)
- `DarkGoldenRod` (a standard X11 colour name, see [FFmpeg colour names](https://github.com/scriptituk/ffmpeg-colours))
- `0x56789A` or `#56789A` (packed RGB hex digits)
- `0.75` (75% grey)

### Custom expression performance

FFmpeg `expr` strings initially get parsed into an expression tree of `AVExpr` nodes in libavutil/eval.c.
That expression is then executed for every pixel in each plane, which obviously incurs a performance hit,
considerably exacerbated by disabling slice threading in order to use the `st()` and `ld()` functions.
So custom transition expressions are not fast.

The following times are based on empirical timings scaled by benchmark scores (the [Geekbench Mac Benchmark Chart](https://browser.geekbench.com/mac-benchmarks)).
They are rough estimates in seconds to process a 3-second transition of HD720 (1280x720) 3-plane media (rgb24) through a null muxer at Mac benchmark midpoints.
For greyscale (single plane), subtract two thirds.
For an alpha plane, add a third.
Mac model performance varies enormously so the Mac vintage dates are only approximate.
Windows performance has not been measured.

| benchmark → <br/> transition ↓ | 2335&#8209;3120 <br/> M1,M2,M3 Macs | 1150&#8209;1655 <br/> 2017&#8209;19 Macs | 700&#8209;1150 <br/> 2013&#8209;16 Macs | 195&#8209;700 <br/> 2008&#8209;12 Macs |
| :---: | :---: | :---: | :---: | :---: |
| `fade` `wipeleft` `wipeup` | 2 | 4 | 6 | 12 |
| `wiperight` `wipedown` | 3 | 6 | 9 | 18 |
| `wipetl` `wipetr` `wipebl` `wipebr` | 5 | 10 | 14 | 30 |
| `squeezeh` `squeezev` | 8 | 16 | 24 | 48 |
| `gl_CornerVanish` | 9 | 18 | 26 | 54 |
| `fadefast` `fadeslow` `rectcrop` | 10 | 20 | 30 | 60 |
| `dissolve` | 12 | 24 | 36 | 72 |
| `gl_Diamond` `gl_DoubleDiamond` `gl_FanUp` `gl_randomNoisex` | 14 | 28 | 42 | 84 |
| `smoothleft` `smoothup` `coverleft` `revealleft` `coverup` `revealup` | 16 | 32 | 48 | 100 |
| `slideleft` `slideup` `slidedown` `circlecrop` `vertopen` `vertclose` `horzopen` `horzclose` `coverright` `revealright` `coverdown` `revealdown` `gl_FanIn` `gl_FanOut` `gl_pinwheel` | 18 | 36 | 54 | 110 |
| `slideright` `smoothright` `smoothdown` `diagtl` `diagtr` `diagbl` `diagbr` | 20 | 40 | 60 | 120 |
| `radial` `gl_CrossOut` | 22 | 42 | 66 | 133 |
| `gl_BookFlip` `gl_heart` `gl_polar_function` | 24 | 46 | 72 | 147 |
| `hlslice` `hrslice` `vdslice` `vuslice` | 28 | 54 | 84 | 171 |
| `circleopen` `circleclose` `gl_angular` `gl_Slides` | 30 | 60 | 88 | 180 |
| `hlwind` `hrwind` `vdwind` `vuwind` `gl_PolkaDotsCurtain` | 32 | 63 | 95 | 200 |
| `gl_WaterDrop` | 36 | 72 | 105 | 220 |
| `fadeblack` `fadewhite` `gl_windowblinds` | 38 | 76 | 114 | 228 |
| `gl_Bounce` `pixelize` `gl_cannabisleaf` `gl_randomsquares` `zoomin` | 42 | 84 | 126 | 260 |
| `gl_Dreamy` `gl_Flower` | 48 | 95 | 140 | 300 |
| `fadegrays` `gl_rotateTransition` | 51 | 100 | 152 | 304 |
| `gl_crosswarp` `gl_ripple` | 54 | 105 | 160 | 336 |
| `gl_DirectionalScaled` | 57 | 114 | 168 | 340 |
| `gl_Rolls` | 60 | 120 | 180 | 360 |
| `gl_doorway` | 63 | 126 | 189 | 380 |
| `gl_RotateScaleVanish` | 66 | 126 | 200 | 400 |
| `gl_Swirl` | 69 | 133 | 200 | 420 |
| `gl_InvertedPageCurl` `gl_squareswire` | 80 | 160 | 240 | 480 |
| `gl_CrazyParametricFun` | 84 | 168 | 252 | 520 |
| `gl_crosshatch` `gl_static_wipe` | 88 | 171 | 260 | 540 |
| `gl_directionalwarp` `gl_rotate_scale_fade` | 95 | 189 | 280 | 580 |
| `gl_cube` `gl_hexagonalize` | 105 | 210 | 304 | 640 |
| `gl_Mosaic` `gl_swap` | 110 | 220 | 320 | 680 |
| `gl_perlin` | 132 | 260 | 400 | 800 |
| `gl_kaleidoscope` | 247 | 480 | 720 | 1500 |
| `gl_powerKaleido` | 1000 | 1960 | 2960 | 6100 |

The slowest supported transition `gl_powerKaleido` is clearly impractical for most purposes!
The most complex transition is `gl_InvertedPageCurl` which involved considerable refactoring;
it omits anti-aliasing for simplicity.

See [xfade-easing.h](src/xfade-easing.h) for the C code transpiled from GLSL that helped to optimize the custom expressions.
See the files in [glsl/](glsl/) refactored from other GLSL transition sources that were used for intermediate testing in the [GL Transition Editor](https://gl-transitions.com/editor).

Using the custom ffmpeg build on M2 Macs, the slowest transition takes just 4 seconds for the same task.
However `gl_Exponential_Swish` with blurring can take 3 minutes!
While much slower than a GPU, CPU processing is at least tolerable.
Unlike built-in xfade transitions the custom ffmpeg C code in [xfade-easing.h](src/xfade-easing.h) deploys a single pixel iterator for all extended transition functions which in turn operate on all planes at once.
And it does not require `-filter_complex_threads 1`.

Performance-wise, custom expressions are slower by a factor of 41 (median), 47 (mean) with a huge standard deviation of 26!

Other faster ways to use GL Transitions with FFmpeg are:
- [gl-transition-scripts](https://www.npmjs.com/package/gl-transition-scripts) includes a Node.js CLI script `gl-transition-render` which can render multiple GL Transitions and images for FFmpeg processing
- [ffmpeg-concat](https://github.com/transitive-bullshit/ffmpeg-concat) is a Node.js package which requires installation and a lot of temporary storage
- [ffmpeg-gl-transition](https://github.com/transitive-bullshit/ffmpeg-gl-transition) is a native FFmpeg filter which requires building ffmpeg from source

---

## Reversing xfade effects

(custom ffmpeg only)

This is a generic xfade `reverse` option that has been added to reverse transition and/or easing effects.
It takes a single digit:

- `0` no reverse (default)  
- `1` swap the inputs and reverse the transition effect  
- `2` reverse the easing effect  
- `3` swap the inputs and reverse the transition and easing effects  

It is necessary to swap the inputs during the reversed transition to match the inputs before and after the transition,
i.e. during the `offset` time and after the `offset`+`duration` time.
This is tricky but not impossible to implement in the [xfade-easing.sh](#cli-script) script for custom expressions.
The script has a `-b` option to pass reverse values through to xfade for the custom ffmpeg variant.

Most standard xfade transitions have reversed equivalents, e.g. `wipeleft` and `wiperight` but few GLSL transitions have.
Unlike standard easings, CSS easings also have no mirror-image reversal mode.

*Example*: using the same CSS Linear coefficients [as above](#linear-easing)  
easing: `'linear(0, 0.5 30%, 0.2 60% 80%, 1)'` transition: `gl_FanUp` reverse: `0`–`3`

![reverse effect](assets/reverse.gif)

There is no `gl_FanDown` transition but reversing `gl_FanUp` provides one.

---

## CLI script

[xfade-easing.sh](src/xfade-easing.sh) is a Bash 4 shell wrapper for ffmpeg. It can:
- generate custom easing and transition expressions for the xfade `expr` parameter
- generate easing graphs via gnuplot (especially useful for CSS easings)
- create demo videos for testing
- concenate visual media with eased transitions for presentations and slideshows.

### Usage
```
FFmpeg XFade easing and extensions version 3.0.3 by Raymond Luckhurst, https://scriptit.uk
Generates custom expressions for rendering eased transitions and easing in other filters,
also creates easing graphs, demo videos, presentations and slideshows
See https://github.com/scriptituk/xfade-easing
Usage: xfade-easing.sh [options] [image/video inputs]
Options:
    -f pixel format (default: rgb24): use ffmpeg -pix_fmts for list
    -t transition name and arguments, if any (default: fade); use -L for list
       args in parenthesis as CSV, e.g.: 'gl_perlin(5,0.1)' (both variants)
       or key=value pairs, e.g.: 'gl_perlin(smoothness=0.1, scale=5)' (custom ffmpeg only)
    -e easing function and arguments, if any (default: linear)
       CSS args in parenthesis as CSV, e.g.: 'cubic-bezier(0.17,0.67,0.83,0.67)'
    -b reverse transition and/or easing effect (custom ffmpeg only) (default: 0)
       1 reverses the inputs and transition effect; 2 reverses the easing; 3 reverses both
    -x expr output filename (default: no expr), accepts expansions, - for stdout
    -a append to expr output file
    -s expr output format string with text expansion (default: '%x')
       %f expands to pixel format, %F to format in upper case
       %e expands to the easing name
       %t expands to the transition name
       %E, %T upper case expansions of %e, %t
       %c expands to the CSS easing arguments
       %a expands to the GL transition arguments; %A to the default arguments (if any)
       %x expands to the generated expr, condensed, intended for inline filterchains
       %X uncondensed version of %x, intended for -/filter_complex script files
       %p expands to the progress easing expression, condensed, for inline filterchains
       %g expands to the generic easing expression (for other filters), condensed
       %z expands to the eased transition expression only, condensed
          for the uneased transition expression only, omit -e option and use %x or %X
       %P, %G, %Z, uncondensed versions of %p, %g, %z, for -/filter_complex script files
       %n inserts a newline
    -p easing plot filename (default: no plot), accepts expansions
       formats: gif, jpg, png, svg, pdf, eps, html <canvas>, from file extension
    -m multiple easings to plot on one graph (default: the -e easing)
       CSV easings with optional legend prefix, e.g. in=cubic-in,out=cubic-out,in-out=cubic
    -q plot title (default: easing name, or Easings for multiple plots)
    -c canvas size for easing plot (default: 640x480, scaled to inches for PDF/EPS)
       format: WxH; omitting W or H keeps aspect ratio, e.g. -z x300 scales W
    -v video output filename (default: no video), accepts expansions
       formats: animated gif, mp4 (x264), webm, mkv (FFV1 lossless), from file extension
       if - then format is the null muxer (no output)
       if -f format has alpha then webm and mkv generate transparent video output
       if gifsicle is available then gifs will be optimised
    -z video size (default: input 1 size)
       format: WxH; omitting W or H keeps aspect ratio, e.g. -z 400x scales H
    -d video transition duration (default: 3s, minimum: 0) (see note after -l)
    -i time between video transitions (default: 1s, minimum: 0) (see note after -l)
    -l video length (default: 5s)
       note: options -d, -i, -l are interdependent: l=ni+(n-1)d for n inputs
       given -t & -l, d is calculated; else given -l, t is calculated; else l is calculated
    -j allow input videos to play within transitions (default: no)
       normally videos only play during the -i time but this sets them playing throughout
    -r video framerate (default: 25fps)
    -n show effect name on video as text (requires the libfreetype library)
    -u video text font size multiplier (default: 1.0)
    -k video stack orientation,gap,colour,padding (default: ,0,white,0), e.g. h,2,red,1
       stacks uneased and eased videos horizontally (h), vertically (v) or auto (a)
       auto selects the orientation that displays easing to best effect
       also stacks transitions with default and custom parameters, eased or not
       videos are only stacked if they are different (nonlinear-eased or customised)
       unstacked videos can be padded using orientation=1, e.g. 1,0,blue,5
    -L list all transitions and easings
    -H show this usage text
    -V show this script version
    -X use custom expressions, not the xfade API that supports xfade-easing natively
       by default native support is detected automatically using ffmpeg --help filter=xfade
       the native API adds an easing option and runs much faster
       e.g. xfade=duration=4:offset=1:easing=quintic-out:transition=wiperight
       e.g. xfade=duration=5:offset=2.5:easing='cubic-bezier(.17,.67,.83,.67)' \
            transition='gl_swap(depth=5,reflection=0.7,perspective=0.6)' (see repo README)
    -I set ffmpeg loglevel to info for -v (default: warning)
    -D dump debug messages to stderr and set ffmpeg loglevel to debug for -v
    -P log xfade progress percentage using custom expression print() function (implies -I)
    -T temporary file directory (default: /tmp)
    -K keep temporary files if temporary directory is not /tmp
Notes:
    1. point the shebang path to a bash4 location (defaults to MacPorts install)
    2. this script requires Bash 4 (2009), ffmpeg, gawk, gsed, seq, also gnuplot for plots
    3. use ffmpeg option -filter_complex_threads 1 (slower!) because xfade expression
       vars used by st() & ld() are shared across slices, therefore not thread-safe
       (the custom ffmpeg build works without -filter_complex_threads 1)
    4. CSS easings are supported in the custom ffmpeg build but not as custom expressions
    4. certain xfade transitions are not implemented as custom expressions because
       they perform aggregation (distance, hblur)
    5. many GLSL transitions are also ported, some of which take customisation parameters
       to override defaults append parameters in parenthesis (see -X above)
    6. certain GLSL transitions are only available in the custom ffmpeg build
    7. many transitions do not lend themselves well to easing, others have easing built in
       easings that overshoot (back & elastic) may cause weird effects!
```
### Generating expr code

Expr code is generated using the `-x` option and customised with the `-s`,`-a` options.

- `xfade-easing.sh -t slideright -e quadratic -x -`  
prints expr for slideright transition with quadratic-in-out easing to stdout
- `xfade-easing.sh -t coverup -e quartic-in -x coverup_quartic-in.txt`  
prints expr for coverup transition with quartic-in easing to file coverup_quartic-in.txt
- `xfade-easing.sh -t coverup -e quartic-in -x %t_%e.txt`  
ditto, using expansion specifiers in file name
- `xfade-easing.sh -t rectcrop -e exponential-out -s "\$expr['%t_%e'] = '%n%X';" -x exprs.php -a`  
appends the following to file exprs.php:
```php
$expr['rectcrop_exponential-out'] = '
st(0, if(eq(P, 0), 0, 2^(-10 * (1 - P))))
;
st(1, abs(ld(0) - 0.5));
if(lt(abs(X - W / 2), ld(1) * W) * lt(abs(Y - H / 2), ld(1) * H),
 if(lt(ld(0), 0.5), B, A),
 if(lt(PLANE,3), 0, 255)
)';
```
- `xfade-easing.sh -t gl_polar_function -s "expr='%n%X'" -x fc-script.txt`  
This is not eased, therefore the expr written to fc-script.txt uses progress `P` directly:
```shell
expr='
st(1, 5);
st(2, X / W - 0.5);
st(3, 0.5 - Y / H);
st(4, atan2(ld(3), ld(2)) - PI / 2);
st(4, cos(ld(1) * ld(4)) / 4 + 1);
st(1, hypot(ld(2), ld(3)));
if(gt(ld(1), ld(4) * (1 - P)), A, B)'
```

### Generating test plots

Plots are generated using the `-p` option and customised with the `-m`,`-q`,`-c` options.

Plot data is logged using the `print` function of the ffmpeg expression evaluator for the first plane and first pixel as xfade progress `P` goes from 1 to 0 at 100fps.

- `xfade-easing.sh -e elastic -p plot-%e.pdf`  
creates a PDF file plot-elastic.pdf of elastic easing
- `xfade-easing.sh -q 'Bounce Easing' -m in=bounce-in,out=bounce-out,in-out=bounce -p %e.png -c 500x`  
creates image file bounce.png of the bounce easing scaled to 500px wide with title and legends:

![bounce plot](assets/bounce.png)

The plots above in [Standard easings](#standard-easings-robert-penner) show test plots for all standard easings and all three modes (in, out and in-out).

### Generating demo videos

Videos are generated using the `-v` option and customised with the `-z`,`-d`,`-i`,`-l`,`-j`,`-r`,`-n`,`-u`,`-k` options.

> [!NOTE]
> all transition effect demos on this page are animated GIFs regardless of the commands shown

#### Timing

Input media is serialised according to the expression
$L=NI+(N-1)D$
where
L is the total video length (option `-l`);
I is the individual display time (option `-i`);
D is the transition duration (option `-d`);
N is the number of inputs.
Transition offsets are spaced accordingly.
Depending on option `-j` and the input media length, pre and post padding is added by frame cloning to ensure enough frames are available for transition processing.
See [Usage](#usage) for the precedence of options `-l`, `-i`, `-d`.

#### Examples

- `xfade-easing.sh -t hlwind -e quintic-in -v windy.gif`
creates an animated GIF image of the hlwind transition with quintic-in easing using default built-in images  
![hlwind quintic-in](assets/windy.gif)

- `xfade-easing.sh -t fadeblack -e circular -v maths.mp4 dot.png cross.png`
creates a MP4 video of the fadeblack transition with circular easing using specified inputs  
![gl_perlin](assets/maths.gif)

- `xfade-easing.sh -t coverdown -e bounce-out -v %t-%e.mp4 wallace.png shaun.png`
creates a video of the coverdown transition with bounce-out easing using expansion specifiers for the output file name  
![coverdown bounce-out](assets/coverdown-bounce-out.gif)

- `xfade-easing.sh -t 'gl_polar_function(25)' -v paradise.mkv -n -u 1.2 islands.png rainbow.png`
creates a lossless (FFV1) video (e.g. for further processing) of an uneased polar_function GL transition with 25 segments annotated in enlarged text  
![gl_polar_function=25](assets/paradise.gif)

- `xfade-easing.sh -t 'gl_Lissajous_Tiles(16,20,0.3,9,3,1,0.8,3,Lavender)' -v lissajous.mp4 titian.png kandinsky.png`
creates a stunning [Lissajous](https://en.wikipedia.org/wiki/Lissajous_curve) effect against a Lavender background demonstrating extensive use of transition parameters  
![gl_Lissajous_Tiles](assets/lissajous.gif)

- `xfade-easing.sh -t 'gl_angular(270,1)' -e exponential -v multiple.mp4 -n -k h -l 20 street.png road.png flowers.png bird.png barley.png`
creates a video of the angular GL transition with parameter `startingAngle=270` (south) and `clockwise=1` (an added parameter) for 5 inputs with fast exponential easing  
![gl_angular=0 exponential](assets/multiple.gif)

- `xfade-easing.sh -t gl_BookFlip -e quartic-out -v book.mp4 -f gray -z 248x -n -k h,2,black,1 alice12.png alice34.png`
creates a simple greyscale page turn with quartic-out easing for a more realistic effect.  
![gl_BookFlip quartic out](assets/book.gif)

- `xfade-easing.sh -t circlecrop -e sinusoidal -v home-away.mp4 -l 10 -d 8 -z 246x -k h,4,LightSkyBlue,2 -n phone.png beach.png`
creates a 10s video with a slow 8s circlecrop xfade transition with sinusoidal easing, horizontally stacked with a 4px `LightSkyBlue` gap (see [Color](https://ffmpeg.org/ffmpeg-utils.html#Color)) and 2px padding  
![circlecrop sinusoidal](assets/home-away.gif)

- `xfade-easing.sh -t gl_InvertedPageCurl -e cubic-in -v score.mp4 -f gray -i 2 -d 3 -z 480x -k 1,0,0xD8D8D8,10 fugue1.png fugue2.png fugue3.png`
a 3s page curl effect, static for 2s, with cubic-in easing using greyscale format (`-k 1,0,colour,padding` creates a border)  
![gl_InvertedPageCurl quadratic ](assets/score.gif)  
🎹 I play [this Bach fugue](https://youtu.be/5IGKLtCrUt0?t=1m17s) on my YouTube channel [digitallegro](https://www.youtube.com/@digitallegro/videos) but the GL InvertedPageCurl there was generated by [ffmpeg-concat](https://github.com/transitive-bullshit/ffmpeg-concat)

- `xfade-easing.sh -t 'gl_PolkaDotsCurtain(10,0.5,0)' -e 'cubic-bezier(0.4,1.2,0.6,-1.1)' -v life.mp4 -l 7 -d 5 -z 500x -f yuv420p -r 30 balloons.png fruits.png`
a GL transition with arguments and cubic-bezier easing, running at 30fps for 7 seconds, processing in YUV (Y'CbCr) colour space throughout  
![gl_PolkaDotsCurtain quadratic ](assets/life.gif)

---

## See also

- [FFmpeg Xfade filter](https://ffmpeg.org/ffmpeg-filters.html#xfade) reference documentation
- [FFmpeg Wiki Xfade page](https://trac.ffmpeg.org/wiki/Xfade) with gallery
- [FFmpeg Expression Evaluation](https://ffmpeg.org/ffmpeg-utils.html#Expression-Evaluation) reference documentation
- [Robert Penner’s Easing Functions](http://robertpenner.com/easing/) the original, from 2001
- [Michael Pohoreski’s Easing Functions](https://github.com/Michaelangel007/easing#tldr-shut-up-and-show-me-the-code) single oarameter versions of Penner’s Functions
- [CSS Easing Functions Level 2](https://drafts.csswg.org/css-easing-2/) W3C Editor’s Draft
- [GL Transitions homepage](https://gl-transitions.com) and [Gallery](https://gl-transitions.com/gallery) and [Editor](https://gl-transitions.com/editor)
- [GL Transitions repository](https://github.com/gl-transitions/gl-transitions) on GitHub
- [OpenGL Reference Pages](https://registry.khronos.org/OpenGL-Refpages/gl4/) and [GLSL Data Types](https://www.khronos.org/opengl/wiki/Data_Type_(GLSL))
- [GLSL Vector and Matrix Operations](https://en.wikibooks.org/wiki/GLSL_Programming/Vector_and_Matrix_Operations) GLSL specific built-in data types and functions
- [The Book of Shaders](https://thebookofshaders.com/) a guide through the universe of Fragment Shaders
- [Shadertoy mrmcsoftware](https://www.shadertoy.com/view/NdGfzG) GLSL video transitions by Mark Craig
- [Shadertoy laserdog](https://www.shadertoy.com/view/ls3cDB) GLSL simple page curl transitions by Andrew Hung; his [breakdown](https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/)
- [libavfilter/vf_xfade.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_xfade.c) xfade source code
- [libavutil/eval.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavutil/eval.c) expr source code
- [ffmpeg-concat](https://github.com/transitive-bullshit/ffmpeg-concat) Node.js package, concats videos with GL Transitions
- [ffmpeg-gl-transition](https://github.com/transitive-bullshit/ffmpeg-gl-transition) native FFmpeg GL Transitions filter
- [gl-transition-render](https://www.npmjs.com/package/gl-transition-scripts) Node.js script to render GL Transitions with images on the CLI
- [Editly](https://github.com/mifi/editly) Node.js CLI tool for assembling videos from clips or images or JSON spec.
