# xfade-easing

### Easing expressions for the FFmpeg XFade filter for use with custom transition expressions.

This is a port of Robert Penner easing equations for the FFmpeg expression evaluator.

It also implements most xfade transitions, some GL Transitions and other transitions, for use with the easing expressions.

Example: wipeleft with cubic easing:
```
ffmpeg -i first.mp4 -i second.mp4 -filter_complex_threads 1 -filter_complex \
       xfade=duration=2:offset=5:transition=custom:expr="'
           st(0, 1-P); st(1, if(gt(P, 0.5), 4*ld(0)^3, 1-4*P^3)); st(0, 1-ld(1));
           if(gt(X, W*ld(0)), B, A)
       '" output.mp4
```
The `expr` is shown on 2 lines for clarity. The first line is the cubic in-out expression $e(P)$ which stores its calculated progress in `st(0)`; the second is the wipeleft transition expression $t(e(P))$ which takes its progress value from `ld(0)` instead of $P$.

> [!NOTE]  
> it appears overly complicated because xfade progress $P$ goes from 1..0 but the easing equations expect 0..1

> [!WARNING] 
> the `-filter_complex_threads 1` ffmpeg option is required because xfade expressions
  are not thread-safe (the st() & ld() functions use xfade context memory) [!WARNING]

cut to the chase
 
