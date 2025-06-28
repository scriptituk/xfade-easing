# Changelog

All notable changes to this project will be documented in this file.  
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.4.1] - 2025-06-28

### Fixed

- `gl_CrossZoom` alpha fade reversed

## [3.4.0] - 2025-02-21

### Added

- Windows build guidelines using new repos
  - [ffmpeg-makexe](https://github.com/scriptituk/ffmpeg-makexe) to make FFmpeg with xfade-easing patch
  - [msys2-vcvars](https://github.com/scriptituk/msys2-vcvars) to ingest MSVC environment variables into Msys2
- `gl_Swirl` transition: added `radius` parameter

### Changed

- C code optimisations

### Fixed

- remove warnings compiling `xfade-easing.h` with MSVC

## [3.3.3] - 2025-01-23

### Changed

- renamed custom expression files for clarity
- sundry custom expression optimisations

## [3.3.2] - 2025-01-22

### Fixed

- `gl_hexagonalize` optimisation fault

## [3.3.1] - 2025-01-21

### Added

- `-o` option to `xfade-easing.sh` script to append ffmpeg options for generated video
- raw encoding for `xfade-easing.sh` generated videos for fast batch processing  
  (to decode: `ffmpeg -f rawvideo -pixel_format <f> -framerate <r> -video_size <s> -i <f.raw> …`)

### Changed

- vp9 (webm) encoding tuned to 1080p in `xfade-easing.sh` script
- sundry custom expression optimisations in `xfade-easing.sh` script
- many README updates

### Fixed

- README: need `-u` unified context patch option in build

## [3.3.0] - 2025-01-10

### Changed

- rounded conversions of pixel coordinates and colour values (custom ffmpeg)
- transparency (grey) now variable from black to white (custom ffmpeg)
- code optimisations and refactored aggregates

### Added

- `gl_Bars` transition by Mark Craig
- `gl_blend` transition by scriptituk (custom ffmpeg only)
- `gl_EdgeTransition` transition by Woohyun Kim (custom ffmpeg only)
- `gl_morph` transition by paniq (custom ffmpeg only)
- `gl_StereoViewer` transition: added `trkMat` parameter
- textured backgrounds feature
- blending discussion in README

### Fixed

- incorrect grey rendering of alpha (custom ffmpeg)

## [3.2.1] - 2024-11-28

### Added

- `gl_ButterflyWaveScrawler` transition by mandubian (custom ffmpeg only)
- `gl_chessboard` transition by lql
- `gl_CrossZoom` transition by rectalogic (custom ffmpeg only)
- `gl_StereoViewer` transition by Ted Schundler (custom ffmpeg only)

### Changed

- all backgrounds now customisable in GLSL-ported transitions
- improved colour parser and processing (custom ffmpeg)
- optimised plane data read/write (custom ffmpeg)

### Fixed

- patch file `vf_xfade.patch` problem
- abort on unbalanced parenthesis in parameter parsing

## [3.1.1] - 2024-11-01

### Changed

- minor custom expression optimisations

## [3.1.0] - 2024-10-22

### Added

- `gl_random` pseudo transition, cycles through shuffled GLSL transition names

### Changed

- standardised colour parameter values:
  - negative for transparent
  - 0.0 to 1.0 for greyscale
  - ffmpeg colour spec for RGBA (custom ffmpeg)
- consolidated background colour parameters, now all called `background`
- simpler `PLANE` tests in custom expressions
- updated and reorganised README details on colour

### Fixed

- transparent backgrounds for non-RGB formats in custom expressions
- `gl_heart` custom expression div zero
- minor issues, efficiencies and improvements

## [3.0.4] - 2024-10-10

### Fixed

- support for FFmpeg version 7.1, `FilterLink` refactoring

## [3.0.3] - 2024-09-28

### Added

- `gl_StarWipe` custom transition expression
- `-g` option for gif transparent colour in `xfade-easing.sh` script

### Changed

- cache transition vars during config in `xfade-easing.h` C file
- optimise `gl_Lissajous_Tiles` in `xfade-easing.h` C file
- README transparency: details about transparent GIFs
- README build instructions: info about external component packages

## [3.0.2] - 2024-09-22

### Added

- `gl_Lissajous_Tiles` transition by Boundless (custom ffmpeg only at present)
- `gl_StarWipe` transition by Ben Lucas (custom ffmpeg only at present)

### Fixed

- colour parameter error parsing sign bit

## [3.0.1] - 2024-09-20

### Added

- `gl_SimplePageCurl` custom transition expression

### Changed

- `gl_SimplePageCurl` add roll shadow on rolled-over side
- README build instructions: use stable not snapshot

## [3.0.0] - 2024-09-15

### Added

- generic xfade `reverse` option to reverse any transition effect or easing or both
- README section [Reversing xfade effects](README.md#reversing-xfade-effects)
- `gl_InvertedPageCurl` option `radius`

### Fixed

- initialise transition vars during thread slice not during config in C version

### Changed

- reorganised README sections that had become disordered

## [2.1.7] - 2024-09-05

### Added

- `gl_SimpleBookCurl` transition by Raymond Luckhurst:
  - 360° curl in any direction to simulate page-forward and page-back
  - variable cylinder radius
  - variable shadow intensity
- `gl_SimplePageCurl` option `greyback` to render overleaf greyscale instead of colour
- README section [Curls and Rolls](README.md#curls-and-rolls)

### Fixed

- `gl_SimplePageCurl` roll rendering radius not diameter

### Changed

- improved performance of C version by initialising transition vars during config

## [2.1.6] - 2024-08-25

### Added

- `gl_SimplePageCurl` transition by Andrew Hung, greatly altered:
  - 360° curl in any direction
  - variable cylinder radius
  - roll rendering option
  - reverse-effect uncurl/unroll option
  - variable underside opacity
  - variable shadow intensity

## [2.1.5] - 2024-08-19

### Fixed

- support for Bash version 5.0, readarray redirection syntax error
- improved support for Ubuntu

## [2.1.4] - 2024-08-12

### Fixed

- support for FFmpeg version 7, deprecated option `-filter_complex_script`

## [2.1.3] - 2024-08-07

### Added

- this CHANGELOG
- 8 GLSL transitions by [Mark Craig](https://www.youtube.com/MrMcSoftware) transpiled from his [38+ Video Transitions](https://www.shadertoy.com/view/NdGfzG) contribution on [shadertoy](https://www.shadertoy.com/):  
  `gl_CornerVanish`, `gl_CrossOut`, `gl_Diamond`, `gl_DoubleDiamond`, `gl_FanIn`, `gl_FanOut`, `gl_FanUp`, `gl_Flower`  
  all but `gl_CornerVanish` take a `smoothing` parameter
- uploaded all GLSL transitions adapted to the GL Transition Specification to [glsl/](glsl/)

### Changed

- all transition parameter names in lowerCamelCase for consistency
- added `angle` parameter to `gl_InvertedPageCurl` which may be 30 or 100 (default)
- added `reverseEffect` parameter to `gl_InvertedPageCurl` for an uncurl effect (only available in custom ffmpeg variant)
- sundry README changes and example animated GIF of `gl_InvertedPageCurl` 30° with uncurl

### Fixed

- removed variable length array in [xfade-easing.h](src/xfade-easing.h), unsupported by some compilers

## [2.1.2] - 2024-04-21

### Fixed

- minor code and documentation improvements

## [2.1.1] - 2024-03-03

### Added

- 6 more GL Transitions transpiled from the [GL Transitions repository](https://github.com/gl-transitions/gl-transitions):  
  `gl_BowTie`, `gl_cannabisleaf`, `gl_crosshatch`, `gl_Exponential_Swish`, `gl_GridFlip`, `gl_heart`, `gl_Stripe_Wipe`, `gl_windowblinds`
- 2 GLSL transitions by Boundless transpiled from the [Vegas Forum post on GL Transitions](https://www.vegascreativesoftware.info/us/forum/gl-transitions-gallery-sharing-place-share-the-code-here--133472/):  
  `gl_Exponential_Swish`, `gl_Stripe_Wipe`

### Changed

- simpler vector math in [xfade-easing.h](src/xfade-easing.h) using inline functions
- transition parameters now saved as static vars during xfade config in [xfade-easing.h](src/xfade-easing.h),
  boosts performance by not processing parameters every call

### Fixed

- README corrections and amendments

## [2.0.0] - 2024-02-11

### Added

- FFmpeg Xfade filter extended by #including [xfade-easing.h](src/xfade-easing.h) in libavfilter/vf_xfade.c, with:
  - new `easing` option
    - 10 standard easing functions by Robert Penner
    - 2 supplementary easing functions
    - 3 CSS Level 2 [easing functions](https://developer.mozilla.org/en-US/docs/Web/CSS/easing-function)
      plus the predefined Cubic Bézier and Step functions
  - altered `transition` option to take additional transitions
  - easing & transitions take optional parameters
  - 32 extended transitions, all [GL Transitions](https://gl-transitions.com/gallery) transpiled from GLSL to C
  - easy install & build

### Changed

- altered CLI wrapper script [xfade-easing.sh](src/xfade-easing.sh) to detect and use the custom build
- wrapper script bugfixes

## [Unreleased]

- previous version changes not logged
