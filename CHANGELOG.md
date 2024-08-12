# Changelog

All notable changes to this project will be documented in this file.  
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
