# xfade-easing

## Overview

This is a port of Robert Penner’s easing equations for the FFmpeg expression evaluator for custom xfade filter transitions.

It also ports most xfade transitions, some GL Transitions and other transitions, for use in tandem with the easing expressions.

<img align="right" src="https://github.com/scriptituk/xfade-easing/assets/35268161/9f98852d-6dde-4d73-a5e9-014b980de6ea">

**Example**: wipeleft with cubic easing:
```
ffmpeg -i first.mp4 -i second.mp4 -filter_complex_threads 1 -filter_complex \
       xfade=duration=3:offset=1:transition=custom:expr="'
           st(0, 1-P); st(1, if(gt(P, 0.5), 4*ld(0)^3, 1-4*P^3)); st(0, 1-ld(1));
           if(gt(X, W*ld(0)), B, A)
       '" output.mp4
```
The `expr` is shown on two lines for clarity. The first line is the easing expression $e(P)$ (cubic in-out) which stores its calculated progress value in `st(0)`; the second is the  transition expression $t(e(P))$ (wipeleft) which loads its eased progress value from `ld(0)` instead of $P$.

> [!NOTE]  
> the example appears overly complicated because xfade progress `P` goes from 1..0 but the easing equations expect 0..1

> [!WARNING] 
> the `-filter_complex_threads 1` ffmpeg option is required because xfade expressions are not thread-safe (the st() & ld() functions use xfade context memory)

## The code
### Compressed code for `-filter_complex`
#### Easing expressions
#### Transition expressions
### Verbose code for -filter_complex_script
#### Easing expressions
#### Transition expressions

## Easings
### Robert Penner easings
### Other easings

## Transitions
### XFade transitions
### GL Transitions
#### GL Transition parameters
### Other transitions

## Code generator CLI script
### Usage
### Examples
#### Generating expression code
#### Generating easing plots
#### Generating demo videos

