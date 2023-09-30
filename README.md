# xfade-easing

## Overview

This is a port of Robert Penner’s easing equations for the FFmpeg expression evaluator for custom xfade filter transitions.

It also ports most xfade transitions, some GL Transitions and other transitions, for use in tandem with the easing expressions.

**Example**: wipedown with cubic easing:

![wipedown-cubic](https://github.com/scriptituk/xfade-easing/assets/35268161/7eb6ff12-41a0-48ba-945c-fcd828cd03b1)
```
ffmpeg -i first.mp4 -i second.mp4 -filter_complex_threads 1 -filter_complex \
       xfade=duration=3:offset=1:transition=custom:expr="'
           st(0, 1 - P); st(1, if(gt(P, 0.5), 4 * ld(0)^3, 1 - 4 * P^3)); st(0, 1 - ld(1));
           if(gt(Y, H * (1 - ld(0))), A, B)
       '" output.mp4
```
The `expr` is shown on two lines for clarity. The first line is the easing expression $e(P)$ (cubic in-out) which stores its calculated progress value in `st(0)`; the second is the  transition expression $t(e(P))$ (wipedown) which loads its eased progress value from `ld(0)` instead of $P$.

> [!NOTE]  
> the example appears overly complicated because xfade progress `P` goes from 1..0 but the easing equations expect 0..1

> [!WARNING] 
> the `-filter_complex_threads 1` ffmpeg option is required because xfade expressions are not thread-safe (the st() & ld() functions use xfade context memory)

## The expr code
### Compressed, for -filter_complex
#### Easings
#### Transitions
### Verbose, for -filter_complex_script
#### Easings
#### Transitions

## The easings
### Robert Penner easings
### Other easings

## The transitions
### XFade transitions
### GL Transitions
#### Parameters
### Other transitions

## Expr code generator CLI script
### Usage
### Examples
#### Generating expression code
#### Generating easing plots
#### Generating demo videos

