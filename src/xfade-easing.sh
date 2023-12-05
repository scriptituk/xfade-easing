#!/opt/local/bin/bash

# FFmpeg Xfade easing expressions by Raymond Luckhurst, Scriptit UK, https://scriptit.uk
# GitHub: owner scriptituk; repository xfade-easing; https://github.com/scriptituk/xfade-easing
#
# This is a port of Robert Penner's easing equations for the FFmpeg expression evaluator
# It also ports most xfade transitions and some GL Transitions for use with easing
#
# See https://github.com/scriptituk/xfade-easing for documentation or use the -H option
# See https://ffmpeg.org/ffmpeg-utils.html#Expression-Evaluation for FFmpeg expressions

set -o posix

export CMD=$(basename $0)
export VERSION=1.8.2
export TMPDIR=/tmp

TMP=$TMPDIR/${CMD%.*}-$$
trap "rm -f $TMP-*" EXIT
ERROR=64 # unreserved exit code
N=$'\n'
R=$'\r'
T=$'\t'

# defaults
export FORMAT=rgb24
export TRANSITION=fade
export EASING=linear
export MODE=inout
export EXPRFORMAT="'%x'"
export PLOTSIZE=640x480 # default for gnuplot (4:3)
export VIDEOSIZE=250x200 # sheep/goat png (5:4)
export VIDEOTRANSITIONDURATION=3
export VIDEOTIME=1
export VIDEOLENGTH=5
export VIDEOFPS=25
export VIDEOSTACK=,0,white,0 # orientation,gap,colour,padding
export VIDEOFSMULT=1.0

# pixel format
p_isrgb= # is RGB
p_maxv= # maximum value of component
p_midv= # mid value of component
p_black= # black value
p_white= # white value

vinputs= # video inputs

# main controlling function
_main() {
    _deps || exit $ERROR # check dependencies
    _opts "$@" || exit $ERROR # get options
    _tmp || exit $ERROR # set tmp dir
    format=${o_format-$FORMAT}
    _format $format || exit $ERROR # set pix format vars
    transition=${o_transition-$TRANSITION}
    [[ $transition =~ = ]] && args=${transition#*=} && transition=${transition%=*}
    easing=${o_easing-$EASING}
    mode=${o_mode-$MODE}
    xformat=${o_xformat-$EXPRFORMAT}

    [[ -n $o_list ]] && _list && exit 0
    [[ -n $o_help ]] && _help && exit 0
    [[ -n $o_version ]] && _version && exit 0

    [[ ! $mode =~ ^(in|out|inout)$ ]] && _error "unknown easing mode '$mode'" && exit $ERROR

    easing_expr=$(_easing $easing $mode) # get easing expr
    [[ -z $easing_expr ]] && _error "unknown easing '$easing'" && exit $ERROR

    transition_expr=$(_transition $transition $args) # get transition expr
    [[ -z $transition_expr ]] && _error "unknown transition '$transition'" && exit $ERROR

    expr=$transition_expr # uneased (linear)
    transition_expr=$(gsed -e "s/\<P\>/ld(0)/g" <<<$transition_expr) # expects eased progress in ld(0)
    if [[ $easing != linear || -n $o_easing ]]; then
        expr="$easing_expr%n;%n$transition_expr" # chained easing & transition
    fi

    [[ -n $o_logprogress ]] && expr="if(ld(9)-st(9,floor(time(0))),print(floor((1-P)*100)))%n;%n$expr"

    [[ -n $o_expr ]] && _expr "$o_expr" "$xformat" # output custom expression
    [[ -n $o_plot ]] && _plot "$o_plot" $easing # output easing plot
    [[ -n $o_video ]] && _video "$o_video" "${vinputs[@]}" # output demo video
}

# emit error message to stderr
_error() { # message
    echo "Error: $1" >&2
}

# extract document contained in this script
_heredoc() { # delimiter
    gsed -n -e "/^@$1/,/^!$1/{//!p}" $0 | gsed '/^[ \t]*#/d'
}

# list all transitions
_list() {
    _heredoc LIST | gawk -f- $0 | gawk -F "$T" '{
        if (/:/ || /^$/)
            print
        else
            print "\t" $1 ($2 ? sprintf(" [args: %s; default: =%s]", $2, $3) : "") ($4 ? sprintf(" (by: %s)", $4) : "")
    }'
}

# emit usage text
_help() {
    _heredoc USAGE | envsubst
}

# emit version
_version() {
    echo $VERSION
}

# check dependencies
_deps() {
    local deps
    [[ ${BASH_VERSINFO[0]} -ge 4 ]] || deps=' bash-v4'
    for s in gawk gsed envsubst gnuplot ffmpeg seq base64; do
        which -s $s || deps+=" $s"
    done
    [[ -n $deps ]] && _error "missing dependencies:$deps" && return $ERROR
    return 0
}

# process CLI options
_opts() {
    local OPTIND OPTARG opt
    while getopts ':f:t:e:m:x:as:p:c:v:z:i:d:l:r:nu:k:LHVIPT:K' opt; do
        case $opt in
        f) o_format=$OPTARG ;;
        t) o_transition=$OPTARG ;;
        e) o_easing=$OPTARG ;;
        m) o_mode=$OPTARG ;;
        x) o_expr=$OPTARG ;;
        a) o_xappend=true ;;
        s) o_xformat=$OPTARG ;;
        p) o_plot=$OPTARG ;;
        c) o_psize=$OPTARG ;;
        v) o_video=$OPTARG ;;
        z) o_vsize=$OPTARG ;;
        d) o_vtduration=$OPTARG ;;
        i) o_vtime=$OPTARG ;;
        l) o_vlength=$OPTARG ;;
        r) o_vfps=$OPTARG ;;
        n) o_vname=true ;;
        u) o_vfsmult=$OPTARG ;;
        k) o_vstack=$OPTARG ;;
        L) o_list=true ;;
        H) o_help=true ;;
        V) o_version=true ;;
        I) o_loglevel=info ;;
        P) o_logprogress=true ; o_loglevel=info ;;
        T) o_tmp=$OPTARG ;;
        K) o_keep=true ;;
        :) _error 'missing argument'; _help; return $ERROR ;;
        \?) _error 'invalid option'; _help; return $ERROR ;;
        esac
    done
    shift $(($OPTIND - 1))
    vinputs=("$@")
    return 0
}

# set tmp dir
_tmp() {
    [[ -z $o_tmp ]] && return 0
    test ! -d $o_tmp && ! mkdir $o_tmp 2>/dev/null && _error "failed to make temp dir $o_tmp" && return $ERROR
    TMP=$o_tmp/${CMD%.*}-$$
    trap - EXIT
    [[ -z $o_keep ]] && trap "rm -f $TMP-* && rmdir $o_tmp 2>/dev/null" EXIT
    return 0
}

# set pixel format
_format() { # pix_fmt
    ffmpeg -hide_banner -pix_fmts > $TMP-pixfmts.txt
    local depth=$(_heredoc PIXFMT | gawk -v format=$1 -f- $TMP-pixfmts.txt)
    [[ -z $depth ]] && _error "unknown format: $1" && return $ERROR
    p_isrgb=0
    [[ $1 =~ (rgb|bgr|gbr|rbg|bggr|rggb) ]] && p_isrgb=1 # (from libavutil/pixdesc.c)
    p_maxv=$(((1<<$depth)-1))
    p_midv=$((1<<($depth-1)))
    if [[ $p_isrgb -ne 0 ]]; then
        p_black='if(lt(PLANE,3), 0, maxv)'
        p_white='maxv'
    else
        p_black='ifnot(PLANE, 0, if(lt(PLANE,3), midv, maxv))'
        p_white='if(between(PLANE,1,2), midv, maxv)'
    fi
    return 0
}

# probe dimension
_dims() { # file
    echo $(ffprobe -v error -i "$1" -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0)
}

# parse size
_size() { # WxH original even
    local w=${1%x*} h=${1#*x} W=${2%x*} H=${2#*x}
    [[ -z $w ]] && w=$(_calc "int($W * $h / $H + 0.5)")
    [[ -z $h ]] && h=$(_calc "int($H * $w / $W + 0.5)")
    [[ -n $3 ]] && w=$(_calc "int($w / 2 + 0.5) * 2") && h=$(_calc "int($h / 2 + 0.5) * 2") # even
    echo "${w}x${h}"
}

# expand path placeholder tokens
_expand() { # format expr
    local e="$1"
    e=${e//%f/$format}
    e=${e//%t/$transition}
    if [[ $e =~ %[aA] ]]; then
        local a=$(_args $transition)
        e=${e//%a/${args-$a}}
        e=${e//%A/$a}
    fi
    e=${e//%e/$easing}
    e=${e//%m/$mode}
    e=${e//%F/${format^^}}
    e=${e//%T/${transition^^}}
    e=${e//%E/${easing^^}}
    e=${e//%M/${mode^^}}
    if [[ $e =~ %[xyzXYZ] ]]; then
        local x=${2-$expr} y=$easing_expr z=$transition_expr
        e=${e/\%X/$x}
        e=${e/\%Y/$y}
        e=${e/\%Z/$z}
        x=${x//%n/} && x=${x// /} # inline
        y=${y//%n/} && y=${y// /}
        z=${z//%n/} && z=${z// /}
        e=${e/\%x/$x}
        e=${e/\%y/$y}
        e=${e/\%z/$z}
    fi
    e=${e//%n/$N}
    echo "$e"
}

# get default transition args
_args() { # transition
    _heredoc LIST | gawk -f- $0 | gawk -F "$T" -v transition=$1 '$1 == transition { if ($3 != "") print $3 }'
}

# get transition author
_author() { # transition
    _heredoc LIST | gawk -f- $0 | gawk -F "$T" -v transition=$1 '$1 == transition { if ($4 != "") print $4 }'
}

# calculate expression using awk
_calc() { # expr
    gawk -e "BEGIN { ORS = \"\"; print ($1) }"
}

# expression builder
_make() { # expr ...
    local e
    for e in "$@"; do
        if [[ -z $e ]]; then
            made=
        elif [[ -z $made ]]; then
            made="$e"
        else
            made+="%n$e"
        fi
    done
}

# C99 % (remainder) operator: a % b = a - (a / b * b) (/ rounds towards 0)
# (not subexpression safe: group first)
_rem() { # a b
    [[ $# -ne 2 ]] && _error "_rem expects 2 args, got $#"
    echo "($1 - trunc($1 / $2) * $2)"
}

# vf_xfade.c fract(a)
# (not subexpression safe: group first)
_fract() { # a
    [[ $# -ne 1 ]] && _error "_fract expects 1 arg, got $#"
    echo "$1 - floor($1)"
}

# vf_xfade.c smoothstep(edge0,edge1,x)
# (not subexpression safe: group first)
_smoothstep() { # edge0 edge1 x st
    [[ $# -ne 4 ]] && _error "_smoothstep expects 4 args, got $#"
    local e n="($3 - $1)" d="($2 - $1)"
    [[ $1 == 0 ]] && n="$3" && d="$2"
    [[ "$2-$1" =~ ^[0-9.-]+$ ]] && d=$(_calc "$d")
    e="$n / $d"
    [[ $d == 1 ]] && e="$n"
    e=${e//- -/+ }
    e="st($4, clip($e, 0, 1))"
    echo "$e * ld($4) * (3 - 2 * ld($4))"
}

# vf_xfade.c frand(x,y)
# (not subexpression safe: group first)
_frand() { # x y st
    [[ $# -ne 3 ]] && _error "_frand expects 3 args, got $#"
    local e="st($3, sin($1 * 12.9898 + $2 * 78.233) * 43758.5453)"
    echo "$e - floor(ld($3))"
}

# get first input value
# (not subexpression safe: group first)
_a() { # X Y
    [[ $# -ne 2 ]] && _error "_a expects 2 args, got $#"
    echo "ifnot(PLANE, a0($1,$2), if(eq(PLANE,1), a1($1,$2), if(eq(PLANE,2), a2($1,$2), a3($1,$2))))"
}

# get second input value
# (not subexpression safe: group first)
_b() { # X Y
    [[ $# -ne 2 ]] && _error "_b expects 2 args, got $#"
    echo "ifnot(PLANE, b0($1,$2), if(eq(PLANE,1), b1($1,$2), if(eq(PLANE,2), b2($1,$2), b3($1,$2))))"
}

# get black/white value
# (not subexpression safe: group first)
_mono() { # W
    [[ $# -ne 1 ]] && _error "_mono expects 1 arg, got $#"
    if [[ $p_isrgb -ne 0 ]]; then
        echo "if($1+eq(PLANE,3), maxv, 0)"
    else
        echo "if(between(PLANE,1,2), midv, if($1+PLANE, maxv, 0))"
    fi
}

# get grey value
# (not subexpression safe: group first)
_grey() { # G
    [[ $# -ne 1 ]] && _error "_grey expects 1 arg, got $#"
    if [[ $p_isrgb -ne 0 ]]; then
        echo "if(eq(PLANE,3), maxv, $1*maxv)"
    else
        echo "if(between(PLANE,1,2), midv, if(PLANE, maxv, $1*maxv))"
    fi
}

# mix linear interpolation
# (not subexpression safe: group first)
_mix() { # a b mix xf
    [[ $# -lt 3 ]] && _error "_mix expects 3 args, got $#"
    if [[ -n $4 ]]; then
        echo "$1 * $3 + $2 * (1 - $3)" # xfade mix fn
    else
        echo "$1 * (1 - $3) + $2 * $3"
    fi
}

# dot product
# (not subexpression safe: group first)
_dot() { # x1 y1 x2 y2
    [[ $# -ne 4 ]] && _error "_dot expects 4 args, got $#"
    echo "$1 * $3 + $2 * $4"
}

# step function
_step() { # edge x
    [[ $# -ne 2 ]] && _error "_step expects 2 args, got $#"
    echo "gte($2, $1)"
}

# custom expressions for standard easings
# (by Robert Penner; single arg version by Michael Pohoreski, optimised by me)
# see http://robertpenner.com/easing/
# see https://github.com/Michaelangel007/easing
_rp_easing() { # easing mode
    local i o io # mode expressions
    local x # expr
    case $1 in
        # note: P is xfade P; Q is 1-P (progress 0 to 1)
    linear)
        io='st(0, P)'
        i="$io"
        o="$io"
        ;;
    quadratic)
        i='st(0, P * (2 - P))'
        o='st(0, P^2)'
        io='st(0, if(gt(P, 0.5), 2 * P * (2 - P) - 1, 2 * P^2))'
        ;;
    cubic)
        i='st(0, 1 - Q^3)'
        o='st(0, P^3)'
        io='st(0, if(gt(P, 0.5), 1 - 4 * Q^3, 4 * P^3))'
        ;;
    quartic)
        i='st(0, 1 - Q^4)'
        o='st(0, P^4)'
        io='st(0, if(gt(P, 0.5), 1 - 8 * Q^4, 8 * P^4))'
        ;;
    quintic)
        i='st(0, 1 - Q^5)'
        o='st(0, P^5)'
        io='st(0, if(gt(P, 0.5), 1 - 16 * Q^5, 16 * P^5))'
        ;;
    sinusoidal)
        i='st(0, sin(P * PI / 2))'
        o='st(0, 1 - cos(P * PI / 2))'
        io='st(0, (1 - cos(P * PI)) / 2)'
        ;;
    exponential)
        i='st(0, if(eq(P, 1), 1, 1 - 2^(-10 * P)))'
        o='st(0, if(eq(P, 0), 0, 2^(-10 * Q)))'
        io='st(0, if(gt(P, 0.5), if(eq(P, 1), 1, 1 - 2^(9 - 20 * P)), if(eq(P, 0), 0, 2^(20 * P - 11))))'
        ;;
    circular)
        i='st(0, sqrt(P * (2 - P)))'
        o='st(0, 1 - sqrt(1 - P^2))'
        io='st(0, if(gt(P, 0.5), 1 + sqrt(1 - 4 * Q^2), 1 - sqrt(1 - 4 * P^2)) / 2)'
        ;;
    elastic)
        i='st(0, 1 - cos(20 * P * PI / 3) / 2^(10 * P))'
        o='st(0, cos(20 * Q * PI / 3) / 2^(10 * Q))'
        _make ''
        _make 'st(0, 1 - 2 * P);'
        _make 'st(1, cos(40 * ld(0) * PI / 9) / 2);'
        _make 'st(0, 2^(10 * ld(0)));'
        _make 'st(0, if(gt(P, 0.5), 1 - ld(1) * ld(0), ld(1) / ld(0)))'
        io=$made
        ;;
    back)
        local K=1.70158 # for -10% back
        local K1=2.70158 # K+1
        local H=1.525 # for back in-out
        local H1=2.525 # H+1
        i='st(0, 1 - Q^2 * (Q * K1 - K))'
        o='st(0, P^2 * (P * K1 - K))'
        io='st(0, if(gt(P, 0.5), 1 - 2 * Q^2 * (2 * Q * H1 - H), 2 * P^2 * (2 * P * H1 - H)))'
        ;;
    bounce)
        _make ''
        _make ' st(1, 121 / 16);'
        _make ' if(lt(P, 4 / 11),'
        _make '  ld(1) * P^2,'
        _make '  if(lt(P, 8 / 11),'
        _make '   ld(1) * (P - 6 / 11)^2 + 3 / 4,'
        _make '   if(lt(P, 10 / 11),'
        _make '    ld(1) * (P - 9 / 11)^2 + 15 / 16,'
        _make '    ld(1) * (P - 21 / 22)^2 + 63 / 64'
        _make '   )'
        _make '  )'
        _make ' )'
        x=$made
        _make '' 'st(0,' "$x" ')'
        i=$made
        x="${x//P/ld(0)}"
        _make '' 'st(0, 1 - P);' 'st(0,' "$x" ');' 'st(0, 1 - ld(0))'
        o=$made
        _make ''
        _make 'st(0, st(2, sgn(P - 0.5)) * (2 * P - 1));'
        _make 'st(0,' "$x" ');'
        _make 'st(0, (1 + ld(2) * ld(0)) / 2)'
        io=$made
        ;;
    esac
    x="$io"
    [[ $2 == in ]] && x="$i"
    [[ $2 == out ]] && x="$o"
    [[ $1 == back ]] && x="${x//H1/$H1}" && x="${x//H/$H}" && x="${x//K1/$K1}" && x="${x//K/$K}"
    echo "$x"
}

# custom expressions for supplementary easings
_se_easing() { # easing mode
    local i o io # mode expressions
    local x # expr
    case $1 in
    squareroot) # opposite to quadratic (not Pohoreski's sqrt)
        i='st(0, 1 - sqrt(Q))'
        o='st(0, sqrt(P))'
        io='st(0, if(gt(P, 0.5), 2 - sqrt(2 * Q), sqrt(2 * P)) / 2)'
    ;;
    cuberoot) # opposite to cubic
        i='st(0, 1 - pow(Q, 1 / 3))'
        o='st(0, pow(P, 1 / 3))'
        io='st(0, if(gt(P, 0.5), 2 - pow(2 * Q, 1 / 3), pow(2 * P, 1 / 3)) / 2)'
    ;;
#   step) # steps at halfway point
#       io='st(1, if(gt(P, 0.5), 0, 1))'
#       i="$io"
#       o="$io"
#       ;;
    esac
    x="$io"
    [[ $2 == in ]] && x="$i"
    [[ $2 == out ]] && x="$o"
    echo "$x"
}

# get easing expression
_easing() { # easing mode
    local x=$(_rp_easing $1 $2) # try RP
    [[ -z $x ]] && x=$(_se_easing $1 $2) # try supplementary
    [[ -z $x ]] && exit $ERROR # unknown easing name
    x="${x//Q/(1 - P)}" # xfade progress goes from 1 to 0
    echo "$x" # f(P) in ld(0)
    exit 0
}

# custom expressions for Xfade transitions
# see https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_xfade.c
_xf_transition() { # transition args
    local x # expr
    local a=(${2//,/ }) # args
    local s r
    _make ''
    case $1 in
    fade)
        _make 'mix(A, B, P)'
        ;;
    fadefast|fadeslow)
        r=1 && s=+
        [[ $1 =~ slow ]] && r=2 && s=-
        _make "st(1, pow(P, 1 + log($r $s abs(A - B) / maxv)));"
        _make 'mix(A, B, ld(1))'
        ;;
    dissolve)
        _make 'st(1, frand(X, Y, 1));'
        _make 'st(1, ld(1) * 2 + P * 2 - 1.5);' # smooth
        _make 'if(gte(ld(1), 0.5), A, B)'
        ;;
    fadeblack|fadewhite)
        s=black; [[ $1 =~ white ]] && s=white
        _make "st(1, $s);" # bg
        _make 'st(2, smoothstep(0.8, 1, P, 2));'
        _make 'st(2, mix(A, ld(1), ld(2)));'
        _make 'st(3, smoothstep(0.2, 1, P, 3));'
        _make 'st(3, mix(ld(1), B, ld(3)));'
        _make 'mix(ld(2), ld(3), P)'
        ;;
    fadegrays)
        if [[ $p_isrgb -ne 0 ]]; then
        _make 'st(1, if(lt(PLANE, 3), (a0(X,Y) + a1(X,Y) + a2(X,Y)) / 3, A));'
        _make 'st(2, if(lt(PLANE, 3), (b0(X,Y) + b1(X,Y) + b2(X,Y)) / 3, B));'
        else
        _make 'if(between(PLANE,1,2), st(1, midv); st(2, midv), st(1, A); st(2, B));'
        fi
        _make 'st(3, smoothstep(0.8, 1, P, 3));'
        _make 'st(1, mix(A, ld(1), ld(3)));'
        _make 'st(3, smoothstep(0.2, 1, P, 3));'
        _make 'st(2, mix(ld(2), B, ld(3)));'
        _make 'mix(ld(1), ld(2), P)'
        ;;
    pixelize)
        _make 'st(1, min(P, 1 - P));' # d
        _make 'st(1, ceil(ld(1) * 50) / 50);' # dist
        _make 'st(2, 2 * ld(1) * min(W, H) / 20);' # sqx
        _make 'st(3, ld(2));' # sqy (== sqx in vf_xfade.c)
        _make 'st(2, if(gt(ld(1), 0), min((floor(X / ld(2)) + 0.5) * ld(2), W - 1), X));' # sx
        _make 'st(3, if(gt(ld(1), 0), min((floor(Y / ld(3)) + 0.5) * ld(3), H - 1), Y));' # sy
        _make 'st(1, a(ld(2), ld(3)));'
        _make 'st(2, b(ld(2), ld(3)));'
        _make 'mix(ld(1), ld(2), P)'
        ;;
    wipeleft)
        _make 'if(gt(X, W * P), B, A)'
        ;;
    wiperight)
        _make 'if(gt(X, W * (1 - P)), A, B)'
        ;;
    wipeup)
        _make 'if(gt(Y, H * P), B, A)'
        ;;
    wipedown)
        _make 'if(gt(Y, H * (1 - P)), A, B)'
        ;;
    wipetl)
        _make 'if(lte(Y, H * P) * lte(X, W * P), A, B)'
        ;;
    wipetr)
        _make 'if(lte(Y, H * P) * gt(X, W * (1 - P)), A, B)'
        ;;
    wipebl)
        _make 'if(gt(Y, H * (1 - P)) * lte(X, W * P), A, B)'
        ;;
    wipebr)
        _make 'if(gt(Y, H * (1 - P)) * gt(X, W * (1 - P)), A, B)'
        ;;
    slideleft|slideright)
        [[ $1 =~ left ]] && s=-
        _make "st(1, trunc(${s}W * P));" # z
        _make 'st(2, ld(1) + X);' # zx
        _make 'st(3, rem(ld(2), W) + W * lt(ld(2), 0));' # zz
        _make 'if(between(ld(2), 0, W - 1),'
        _make ' b(ld(3), Y),'
        _make ' a(ld(3), Y)'
        _make ')'
        ;;
    slideup|slidedown)
        [[ $1 =~ up ]] && s=-
        _make "st(1, trunc(${s}H * P));" # z
        _make 'st(2, ld(1) + Y);' # zy
        _make 'st(3, rem(ld(2), H) + H * lt(ld(2), 0));' # zz
        _make 'if(between(ld(2), 0, H - 1),'
        _make ' b(X, ld(3)),'
        _make ' a(X, ld(3))'
        _make ')'
        ;;
    smoothleft|smoothright|smoothup|smoothdown)
        s='X / W'
        [[ $1 =~ right ]] && s='(W - 1 - X) / W'
        [[ $1 =~ up ]] && s='Y / H'
        [[ $1 =~ down ]] && s='(H - 1 - Y) / H'
        _make "st(1, 1 + $s - P * 2);" # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    circlecrop)
        _make "st(1, ${a[0]-0});" # backWhite
        _make 'st(2, (2 * abs(P - 0.5))^3 * hypot(W / 2, H / 2));' # z
        _make 'st(3, hypot(X - W / 2, Y - H / 2));' # dist
        _make 'if(lt(ld(2), ld(3)),'
        _make ' mono(ld(1)),' # bg
        _make ' if(lt(P, 0.5), B, A)' # val
        _make ')'
        ;;
    rectcrop)
        _make "st(1, ${a[0]-0});" # backWhite
        _make 'st(2, abs(P - 0.5) * W);' # zw
        _make 'st(3, abs(P - 0.5) * H);' # zh
        _make 'if(lt(abs(X - W / 2), ld(2)) * lt(abs(Y - H / 2), ld(3)),' # dist
        _make ' if(lt(P, 0.5), B, A),' # val
        _make ' mono(ld(1))' # bg
        _make ')'
        ;;
    circleopen|circleclose)
        _make 'st(1, hypot(W / 2, H / 2));' # z
        s='(P - 0.5) * 3'
        [[ $1 =~ close ]] && s='(0.5 - P) * 3'
        _make "st(2, $s);" # p
        _make 'st(1, hypot(X - W / 2, Y - H / 2) / ld(1) + ld(2));' # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        s='mix(A, B, ld(1))'
        [[ $1 =~ close ]] && s='mix(B, A, ld(1))'
        _make "$s"
        ;;
    vertopen|vertclose|horzopen|horzclose)
        s='2 * X / W - 1'
        [[ $1 =~ horz ]] && s='2 * Y / H - 1'
        r="2 - abs($s) - P * 2"
        [[ $1 =~ close ]] && r="1 + abs($s) - P * 2"
        _make "st(1, $r);" # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    diagtl|diagtr|diagbl|diagbr)
        s='X / W'
        r='Y / H'
        [[ $1 =~ r ]] && s='(W - 1 - X) / W'
        [[ $1 =~ b ]] && r='(H - 1 - Y) / H'
        _make "st(1, 1 + $s * $r - P * 2);" # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    hlslice|hrslice|vuslice|vdslice)
        s='X / W'
        [[ $1 =~ hr ]] && s='(W - 1 - X) / W'
        [[ $1 =~ vu ]] && s='Y / H'
        [[ $1 =~ vd ]] && s='(H - 1 - Y) / H'
        _make "st(1, $s);" # xx, yy
        _make 'st(2, ld(1) - P * 1.5);'
        _make 'st(2, smoothstep(-0.5, 0, ld(2), 2));' # smooth
        _make 'st(1, 10 * ld(1));'
        _make 'st(1, fract(ld(1)));'
        _make 'if(gt(ld(2), ld(1)), B, A)'
        ;;
    radial)
        _make 'st(1, atan2(X - W / 2, Y - H / 2) - (P - 0.5) * PI * 2.5);' # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    zoomin)
        _make 'st(1, smoothstep(0.5, 1, P, 1));' # zf
        _make 'st(2, 0.5 + (X / W - 0.5) * ld(1));' # u
        _make 'st(3, 0.5 + (Y / H - 0.5) * ld(1));' # v
        _make 'st(2, ceil(ld(2) * (W - 1)));' # iu
        _make 'st(3, ceil(ld(3) * (H - 1)));' # iv
        _make 'st(1, a(ld(2), ld(3)));' # zv
        _make 'st(2, smoothstep(0, 0.5, P, 2));'
        _make 'mix(ld(1), B, ld(2))'
        ;;
    squeezeh)
        _make 'st(1, 0.5 + (Y / H - 0.5) / P);' # z
        _make 'if(between(ld(1), 0, 1),'
        _make ' st(1, round(ld(1) * (H - 1)));'
        _make ' a(X, ld(1)),'
        _make ' B'
        _make ')'
        ;;
    squeezev)
        _make 'st(1, 0.5 + (X / W - 0.5) / P);' # z
        _make 'if(between(ld(1), 0, 1),'
        _make ' st(1, round(ld(1) * (W - 1)));'
        _make ' a(ld(1), Y),'
        _make ' B'
        _make ')'
        ;;
    hlwind|hrwind|vuwind|vdwind)
        s='X / W'
        [[ $1 =~ v ]] && s='Y / H'
        [[ $1 =~ l || $1 =~ u ]] && s="1 - $s"
        _make "st(1, $s);" # fx, fy
        r='frand(0, Y, 2)'
        [[ $1 =~ v ]] && r='frand(X, 0, 2)'
        _make "st(2, $r);" # r
        _make 'st(1, ld(1) * 0.8 + 0.2 * ld(2) - (1 - P) * 1.2);'
        _make 'st(1, smoothstep(0, -0.2, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    coverleft|coverright|revealleft|revealright)
        [[ $1 =~ left ]] && s=-
        _make "st(1, trunc(${s}W * P));" # z
        _make 'st(2, ld(1) + X);' # zx
        _make 'st(3, rem(ld(2), W) + W * lt(ld(2), 0));' # zz
        r='b(ld(3), Y)' && s=A
        [[ $1 =~ reveal ]] && r=B && s='a(ld(3), Y)'
        _make 'if(between(ld(2), 0, W - 1),'
        _make " $r,"
        _make " $s"
        _make ')'
        ;;
    coverup|coverdown|revealup|revealdown)
        [[ $1 =~ up ]] && s=-
        _make "st(1, trunc(${s}H * P));" # z
        _make 'st(2, ld(1) + Y);' # zy
        _make 'st(3, rem(ld(2), H) + H * lt(ld(2), 0));' # zz
        r='b(X, ld(3))' && s=A
        [[ $1 =~ reveal ]] && r=B && s='a(X, ld(3))'
        _make 'if(between(ld(2), 0, H - 1),'
        _make " $r,"
        _make " $s"
        _make ')'
        ;;
#   distance) needs number of planes
#   hblur) needs aggregation in X
    esac
    x=$made
    echo "$x"
}

# custom expressions for GL Transitions
# # see https://github.com/gl-transitions/gl-transitions/tree/master/transitions
_gl_transition() { # transition args
    local x # expr
    local a=(${2//,/ }) # args
    _make ''
    case $1 in
    # NOTE 1: never use P after st(0) as it will break easing
    # NOTE 2: if st(9) is needed restore its time value as in gl_powerKaleido
    gl_angular) # by Fernando Kuteken
        _make "st(1, ${a[0]-90});" # startingAngle
        _make "st(2, ${a[1]-0});" # goClockwise
        _make 'st(3, 1 - P);' # progress
        _make 'st(1, ld(1) * PI / 180);' # offset
        _make 'st(1, atan2(0.5 - Y / H, X / W - 0.5) + ld(1));' # angle
        _make 'st(1, (ld(1) + PI) / (2 * PI));' # normalizedAngle
        _make 'if(ld(2), st(1, -ld(1)));'
        _make 'st(1, fract(ld(1)));'
        _make 'if(step(ld(1), ld(3)), B, A)'
        ;;
    gl_BookFlip) # by hong
        _make 'st(1, X / W - 0.5);'
        _make 'st(2, 0.5 - Y / H);'
        _make 'st(3, gte(X / W, P));' # pr
        _make 'if(lt(ld(1), 0),'
        _make ' st(4, ld(1) / (0.5 - P) / 2 + 0.5);' # skewLeft skewX
        _make ' st(5, ld(2) / (0.5 - P * ld(1) * 2) / 2 + 0.5);' # skewLeft skewY
        _make ' st(4, ld(4) * W);'
        _make ' st(5, (1 - ld(5)) * H);'
        _make ' st(5, b(ld(4), ld(5)));'
        _make ' st(4, A);'
        if [[ $p_isrgb -ne 0 ]]; then
        _make ' if(st(6, lt(PLANE, 3)),'
        else
        _make ' if(st(6, not(PLANE)),'
        fi
        _make '  st(5, ld(5) * max(0.7, abs(P - 0.5) * 2))' # shadeVal
        _make ' ),'
        _make ' st(4, (ld(1) - 0.5 + P) / (P - 0.5) / 2);' # skewRight skewX
        _make ' st(5, ld(2) / (0.5 + (1 - P) * ld(1) * 2) / 2 + 0.5);' # skewRight skewY
        _make ' st(4, ld(4) * W);'
        _make ' st(5, (1 - ld(5)) * H);'
        _make ' st(4, a(ld(4), ld(5)));'
        _make ' st(5, B);'
        _make ' if(ld(6),'
        _make '  st(4, ld(4) * max(0.7, abs(P - 0.5) * 2))' # shadeVal
        _make ' )'
        _make ');'
        _make 'mix(ld(4), ld(5), ld(3))'
        ;;
    gl_Bounce) # by Adrian Purser
        _make "st(1, ${a[0]-0.6});" # shadow_alpha
        _make "st(2, ${a[1]-0.075});" # shadow_height
        _make "st(3, ${a[2]-3});" # bounces
        _make 'st(4, 1 - P);' # progress
        _make 'st(3, ld(4) * PI * ld(3));' # phase
        _make 'st(3, abs(cos(ld(3))) * (1 - sin(ld(4) * PI / 2)));' # y
        _make 'st(5, 1 - Y / H - ld(3));' # d
        _make 'st(4, smoothstep(0.95, 1, ld(4), 4));'
        _make 'st(6, ld(5) / ld(2) * ld(1) + (1 - ld(1)));'
        _make 'st(6, mix(ld(6), 1, ld(4)));'
        _make 'st(6, step(ld(5), ld(2)) * (1 - ld(6)));'
        _make 'st(1, black);'
        _make 'st(1, mix(B, ld(1), ld(6)));'
        _make 'st(2, Y - (1 - ld(3)) * H);'
        _make 'st(2, a(X, ld(2)));'
        _make 'st(3, step(ld(5), 0));'
        _make 'mix(ld(1), ld(2), ld(3))'
        ;;
    gl_CrazyParametricFun) # by mandubian
        _make "st(1, ${a[0]-4});" # a
        _make "st(2, ${a[1]-1});" # b
        _make "st(3, ${a[2]-120});" # amplitude
        _make "st(4, ${a[3]-0.1});" # smoothness
        _make 'st(5, 1 - P);' # progress
        _make 'st(6, ld(1) - ld(2));'
        _make 'st(7, ld(1) / ld(2) - 1);'
        _make 'st(1, ld(6) * cos(ld(5)) + ld(2) * cos(ld(5) * ld(7)));' # x
        _make 'st(2, ld(6) * sin(ld(5)) - ld(2) * sin(ld(5) * ld(7)));' # y
        _make 'st(6, X / W - 0.5);' # dir.x
        _make 'st(7, 0.5 - Y / H);' # dir.y
        _make 'st(8, hypot(ld(6), ld(7)));' # dist
        _make 'st(8, ld(5) * ld(8) * ld(3));'
        _make 'st(1, ld(6) * sin(ld(8) * ld(1)) / ld(4));' # offset.x
        _make 'st(2, ld(7) * sin(ld(8) * ld(2)) / ld(4));' # offset.y
        _make 'st(1, (X / W + ld(1)) * W);'
        _make 'st(2, (1 - ((1 - Y / H) + ld(2))) * H);'
        _make 'st(1, a(ld(1), ld(2)));';
        _make 'st(2, smoothstep(0.2, 1, ld(5), 2));'
        _make 'mix(ld(1), B, ld(2))'
        ;;
    gl_crosswarp) # by Eke Péter
        _make 'st(1, (1 - P) * 2 + X / W - 1);'
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'st(2, X / W - 0.5);'
        _make 'st(3, 0.5 - Y / H);'
        _make 'st(4, (ld(2) * (1 - ld(1)) + 0.5) * W);'
        _make 'st(5, (0.5 - (ld(3) * (1 - ld(1)))) * H);'
        _make 'st(6, a(ld(4), ld(5)));'
        _make 'st(4, (ld(2) * ld(1) + 0.5) * W);'
        _make 'st(5, (0.5 - (ld(3) * ld(1))) * H);'
        _make 'st(7, b(ld(4), ld(5)));'
        _make 'mix(ld(6), ld(7), ld(1))'
        ;;
    gl_cube) # by gre
        _make "st(1, ${a[0]-0.7});" # persp
        _make "st(2, ${a[1]-0.3});" # unzoom
        _make "st(3, ${a[2]-0.4});" # reflection
        _make "st(4, ${a[3]-3});" # floating
        _make 'st(0, 1 - P);' # progress
        _make 'st(2, ld(2) * 2 * (0.5 - abs(0.5 - ld(0))));' # ux
        _make 'st(7, X / W * (1 + ld(2)) - ld(2) / 2);' # p.x
        _make 'st(8, (1 - Y / H) * (1 + ld(2)) - ld(2) / 2);' # p.y
        _make 'st(2, ld(0) * (1 - ld(1)));' # persp2
        _make 'st(5, (ld(7) - ld(0)) / (1 - ld(0)));' # fromP.x
        _make 'st(6, (ld(8) - ld(2) * ld(5) / 2) / (1 - ld(2) * ld(5)));' # fromP.y
        _make 'st(2, ld(0) * ld(0));'
        _make 'st(2, 1 - (mix(ld(2), 1, ld(1))));' # persp2
        _make 'st(1, ld(7) / ld(0));' # toP.x
        _make 'st(2, (ld(8) - ld(2) * (1 - ld(1)) / 2) / (1 - ld(2) * (1 - ld(1))));' # toP.y
        _make 'ifnot(st(0, -between(ld(5), 0, 1) * between(ld(6), 0, 1)),' # inBounds(fromP)
        _make ' ifnot(st(0, between(ld(1), 0, 1) * between(ld(2), 0, 1)),' # inBounds(toP)
        _make '  st(2, ld(2) * -1.2 - ld(4) / 100);'
        _make '  ifnot(st(0, 2 * between(ld(1), 0, 1) * between(ld(2), 0, 1)),'
        _make '   st(6, ld(6) * -1.2 - ld(4) / 100);'
        _make '   st(0, -2 * between(ld(5), 0, 1) * between(ld(6), 0, 1))'
        _make '  )'
        _make ' )'
        _make ');'
        _make "st(4, ${a[4]-0});" # backWhite
        _make 'if(ld(0),'
        _make ' if(lt(ld(0), 0), st(1, ld(5)); st(2, ld(6)));'
        _make ' st(5, ld(1) * W);'
        _make ' st(6, (1 - ld(2)) * H);'
        _make ' if(lt(ld(0), 0),'
        _make '  st(1, a(ld(5), ld(6))),'
        _make '  st(1, b(ld(5), ld(6)))'
        _make ' );'
        _make ' if(eq(abs(ld(0)), 2),'
        _make '  st(3, ld(3) * (1 - ld(2)));'
        _make '  st(4, mono(ld(4)));'
        _make '  mix(ld(4), ld(1), ld(3)),'
        _make '  ld(1)'
        _make ' ),'
        _make ' mono(ld(4))'
        _make ')'
        ;;
    gl_DirectionalScaled) # by Thibaut Foussard
        _make "st(1, ${a[0]-0});" # direction.x
        _make "st(2, ${a[1]-1});" # direction.y
        _make "st(3, ${a[2]-0.7});" # scale
        _make "st(4, ${a[3]-0});" # backWhite
        _make 'st(5, 1 - P);' # progress
        _make 'st(3, 1 - (1 - 1 /ld(3)) * sin(ld(5) * PI));' # s
        _make 'st(5, pow(sin(ld(5) * PI / 2), 3));' # easedProgress
        _make 'st(1, X / W + ld(5) * sgn(ld(1)));' # p.x
        _make 'st(2, (1 - Y / H) + ld(5) * sgn(ld(2)));' # p.y
        _make 'st(5, (fract(ld(2)) - 0.5) * ld(3) + 0.5);' # f.y
        _make 'st(3, (fract(ld(1)) - 0.5) * ld(3) + 0.5);' # f.x
        _make 'st(6, step(0, ld(2)) * step(ld(2), 1) * step(0, ld(1)) * step(ld(1), 1));' # mixer
        _make 'st(7, ld(3) * W);'
        _make 'st(8, (1 - ld(5)) * H);'
        _make 'st(1, a(ld(7), ld(8)));'
        _make 'st(2, b(ld(7), ld(8)));'
        _make 'st(6, if(ld(6), ld(1), ld(2)));' # col
        _make 'st(1, 1 - ld(3));'
        _make 'st(2, 1 - ld(5));'
        _make 'st(1, step(0, ld(3)) * step(0, ld(1)) * step(0, ld(5)) * step(0, ld(2)));' # border
        _make 'if(ld(1), ld(6), mono(ld(4)))'
        ;;
    gl_directionalwarp) # by pschroen
        _make "st(1, ${a[0]-0.1});" # smoothness
        _make "st(2, ${a[1]--1});" # direction.x
        _make "st(3, ${a[2]-1});" # direction.y
        _make 'st(4, hypot(ld(2), ld(3)));'
        _make 'st(2, ld(2) / ld(4));' # v.x
        _make 'st(3, ld(3) / ld(4));' # v.y
        _make 'st(4, abs(ld(2)) + abs(ld(3)));'
        _make 'st(2, ld(2) / ld(4));'
        _make 'st(3, ld(3) / ld(4));'
        _make 'st(4, (ld(2) + ld(3)) / 2);' # d
        _make 'st(4, ld(2) * X / W + ld(3) * (1 - Y / H) - (ld(4) - 0.5 + (1 - P) * (1 + ld(1))));'
        _make 'st(1, 1 - smoothstep(-ld(1), 0, ld(4), 1));' # m
        _make 'st(2, X / W - 0.5);'
        _make 'st(3, 0.5 - Y / H);'
        _make 'st(4, (ld(2) * (1 - ld(1)) + 0.5) * W);'
        _make 'st(5, (0.5 - ld(3) * (1 - ld(1))) * H);'
        _make 'st(6, a(ld(4), ld(5)));'
        _make 'st(4, (ld(2) * ld(1) + 0.5) * W);'
        _make 'st(5, (0.5 - ld(3) * ld(1)) * H);'
        _make 'st(7, b(ld(4), ld(5)));'
        _make 'mix(ld(6), ld(7), ld(1))'
        ;;
    gl_doorway) # by gre
        _make "st(1, ${a[0]-0.4});" # reflection
        _make "st(2, ${a[1]-0.4});" # perspective
        _make "st(3, ${a[2]-3});" # depth
        _make "st(4, ${a[3]-0});" # backWhite
        _make 'st(0, 1 - P);' # progress
        _make 'st(5, X / W);' # p.x
        _make 'st(6, 1 - Y / H);' # p.y
        _make 'st(7, 0);' # 0 for back
        _make 'st(8, 2 * abs(ld(5) - 0.5) - ld(0));' # middleSlit
        _make 'if(gt(ld(8), 0),'
        _make ' st(8, 1 / (1 + ld(2) * ld(0) * (1 - ld(8))));' # d
        _make ' st(5, ld(5) + (1 - gt(ld(5), 0.5) * 2) * ld(0) / 2);' # pfr.x
        _make ' st(6, (ld(6) + (1 - ld(8)) / 2) * ld(8));' # pfr.y
        _make ' st(7, between(ld(5), 0, 1) * between(ld(6), 0, 1)),' # 1 for getFromColor
        _make ' st(8, 1 - ld(0));'
        _make ' st(8, mix(1, ld(3), ld(8)));' # size
        _make ' st(5, (ld(5) - 0.5) * ld(8) + 0.5);' # pto.x
        _make ' st(6, (ld(6) - 0.5) * ld(8) + 0.5);' # pto.y
        _make ' st(7, 2 * between(ld(5), 0, 1) * between(ld(6), 0, 1));' # 2 for getToColor
        _make ' ifnot(ld(7),'
        _make '  st(6, ld(6) * -1.2 - 0.02);'
        _make '  st(7, 3 * between(ld(5), 0, 1) * between(ld(6), 0, 1))' # 3 for getToColor mix
        _make ' )'
        _make ');'
        _make 'if(ld(7),'
        _make ' st(2, ld(5) * W);'
        _make ' st(3, (1 - ld(6)) * H);'
        _make ' if(eq(ld(7), 1),'
        _make '  a(ld(2), ld(3)),'
        _make '  st(3, b(ld(2), ld(3)));'
        _make '  if(eq(ld(7), 2),'
        _make '   ld(3),'
        _make '   st(4, mono(ld(4)));'
        _make '   st(1, ld(1) * (1 - ld(6)));'
        _make '   mix(ld(4), ld(3), ld(1))'
        _make '  )'
        _make ' ),'
        _make ' mono(ld(4))'
        _make ')'
        ;;
    gl_Dreamy) # by mikolalysenko
        _make 'st(1, X / W);' # p.x
        _make 'st(2, 1 - Y / H);' # p.y
        _make 'st(3, 1 - P);' # progress
        _make 'st(4, cos(10 * (ld(3) + ld(1))));'
        _make 'st(5, 0.03 * ld(3) * ld(4));' # shifty
        _make 'st(5, ld(2) + ld(5));'
        _make 'st(5, (1 - ld(5)) * H);'
        _make 'st(5, a(X, ld(5)));'
        _make 'st(6, 0.03 * (1 - ld(3)) * ld(4));' # shifty
        _make 'st(6, ld(2) + ld(6));'
        _make 'st(6, (1 - ld(6)) * H);'
        _make 'st(6, b(X, ld(6)));'
        _make 'mix(ld(5), ld(6), ld(3))'
        ;;
    gl_hexagonalize) # by Fernando Kuteken
        _make "st(1, ${a[0]-50});" # steps
        _make "st(2, ${a[1]-20});" # horizontalHexagons
        _make 'st(0, 1 - P);' # progress
        _make 'st(3, 2 * min(ld(0), 1 - ld(0)));' # dist
        _make 'if(gt(ld(1), 0), st(3, ceil(ld(3) * ld(1)) / ld(1)));'
        _make 'if(gt(ld(3), 0),'
        _make ' st(2, st(1, sqrt(3)) / 3 * ld(3) / ld(2));' # size
        # hexagonFromPoint
        _make ' st(3, (X / W - 0.5) / ld(2));' # point.x
        _make ' st(4, ((H - Y) / W - 0.5) / ld(2));' # point.y
        _make ' st(3, (ld(1) * ld(3) - ld(4)) / 3);' # hex.q
        _make ' st(4, 2 / 3 * ld(4));' # hex.r
        _make ' st(5, -ld(3) - ld(4));' # hex.s
        # roundHexagon
        _make ' st(6, floor(ld(3) + 0.5));' # q
        _make ' st(7, floor(ld(4) + 0.5));' # r
        _make ' st(8, floor(ld(5) + 0.5));' # s
        _make ' st(3, abs(ld(6) - ld(3)));' # deltaQ
        _make ' st(4, abs(ld(7) - ld(4)));' # deltaR
        _make ' st(5, abs(ld(8) - ld(5)));' # deltaS
        _make ' if(gt(ld(3), ld(4)) * gt(ld(3), ld(5)),'
        _make '  st(6, -ld(7) - ld(8)),'
        _make '  if(gt(ld(4), ld(5)), st(7, -ld(6) - ld(8)))'
        _make ' );'
        # pointFromHexagon
        _make ' st(3, ld(1) * (ld(6) + ld(7) / 2) * ld(2) + 0.5);' # x
        _make ' st(4, 3 / 2 * ld(7) * ld(2) + 0.5);' # y
        _make ' st(3, ld(3) * W);'
        _make ' st(4, H - ld(4) * W);'
        _make ' st(1, a(ld(3), ld(4)));'
        _make ' st(2, b(ld(3), ld(4)));'
        _make ' mix(ld(1), ld(2), ld(0)),'
        _make ' mix(A, B, ld(0))'
        _make ')'
        ;;
    gl_InvertedPageCurl) # by Hewlett-Packard
        # see https://github.com/scriptituk/xfade-easing/blob/main/src/InvertedPageCurl-simplified.glsl
        local MIN_AMOUNT=-0.16;
        local MAX_AMOUNT=1.5;
        local ANGLE=$(_calc "100 * atan2(0, -1) / 180"); # 100 * PI / 180
        local C=$(_calc "cos($ANGLE)"); # -0.173649
        local S=$(_calc "sin($ANGLE)"); # 0.984808
        _make "st(0, (1 - P) * ($MAX_AMOUNT - $MIN_AMOUNT) + $MIN_AMOUNT);" # amount,cylinderCenter
        _make 'st(1, 1 / 2 / PI);' # cylinderRadius
        _make 'st(2, ld(0) / ld(1));' # cylinderAngle
        _make 'st(3, X / W);' # p.x
        _make 'st(4, 1 - Y / H);' # p.y
        _make "st(6, -$S * ld(3) + $C * ld(4) + 0.89);" # point.y
        _make 'st(7, ld(6) - ld(0));' # yc
        _make 'if(gt(ld(7), ld(1)),' # flat surface
        _make ' st(3, A),' # colour
        _make " st(9, $C * ld(3) + $S * ld(4) - 0.801);" # point.x
        _make ' if(lt(ld(7), -ld(1)),' # behind surface
        _make '  st(7, -2 * ld(1) - ld(7));'
        _make '  st(8, acos(ld(7) / ld(1)) + ld(2) - PI);' # hitAngle
        _make '  st(6, ld(8) * ld(1));'
        _make "  st(5, $C * ld(9) - $S * ld(6) + 0.985);" # point.x
        _make "  st(6, $S * ld(9) + $C * ld(6) + 0.985);" # point.y
        _make '  if(lt(ld(7), 0) * between(ld(5), 0, 1) * between(ld(6), 0, 1) * (lt(ld(8), PI) + gt(ld(0), 0.5)),'
        _make '   st(8, (1 - hypot(ld(5) - 0.5, ld(6) - 0.5) * 1.414) * pow(-ld(7) / ld(1), 3) / 2);' # shado
        _make '   st(8, clip(ld(8) * maxv, 0, B)),' # prevent -ve texture
        _make '   st(8, 0)'
        _make '  );'
        if [[ $p_isrgb -ne 0 ]]; then
        _make '  st(3, if(lt(PLANE, 3), B - ld(8), B)),'
        else
        _make '  st(3, ifnot(PLANE, B - ld(8), B)),'
        fi
        _make '  st(3,' # seeThrough
        _make '   st(8, PI - acos(ld(7) / ld(1)) + ld(2));' # hitAngle
        _make '   if(gt(ld(7), 0),'
        _make '    A,'
        _make '    st(4, ld(8) * ld(1));'
        _make "    st(5, $C * ld(9) - $S * ld(4) + 0.985);" # pt.x
        _make "    st(6, $S * ld(9) + $C * ld(4) + 0.985);" # pt.y
        _make '    if(between(ld(5), 0, 1) * between(ld(6), 0, 1),'
        _make '     st(5, ld(5) * W);'
        _make '     st(6, (1 - ld(6)) * H);'
        _make '     a(ld(5), ld(6)),'
        _make '     B'
        _make '    )'
        _make '   )'
        _make '  );'
        _make '  st(8, 2 * ld(2) - ld(8));' # hitAngle
        _make '  st(4, mod(ld(8), 2 * PI));' # hitAngleMod
        _make '  ifnot(gt(ld(4), PI) * lt(ld(0), 0.5) + gt(ld(4), PI / 2) * lt(ld(0), 0),' # seeThroughWithShadow
        _make '   st(4, ld(8) * ld(1));'
        _make "   st(5, $C * ld(9) - $S * ld(4) + 0.985);" # point.x
        _make "   st(6, $S * ld(9) + $C * ld(4) + 0.985);" # point.y
        # distanceToEdge
        _make '   st(8, if(lt(ld(5), 0), -ld(5), if(gt(ld(5), 1), ld(5) - 1, if(gt(ld(5), 0.5), 1 - ld(5), ld(5)))));' # dx
        _make '   st(9, if(lt(ld(6), 0), -ld(6), if(gt(ld(6), 1), ld(6) - 1, if(gt(ld(6), 0.5), 1 - ld(6), ld(6)))));' # dy
        _make '   st(8, if(between(ld(5), 0, 1) + between(ld(6), 0, 1), min(ld(8), ld(9)), hypot(ld(8), ld(9))));' # dist
        _make '   st(8, (1 - ld(8) * 30) / 3);' # shado
        _make '   st(8, clip(ld(8) * ld(0) * maxv, 0, ld(3)));'
        if [[ $p_isrgb -ne 0 ]]; then
        _make '   if(lt(PLANE, 3), st(3, ld(3) - ld(8)));'
        else
        _make '   ifnot(PLANE, st(3, ld(3) - ld(8)));'
        fi
        _make '   if(between(ld(5), 0, 1) * between(ld(6), 0, 1),' # backside
        _make '    st(5, ld(5) * W);'
        _make '    st(6, (1 - ld(6)) * H);'
        _make '    if(lt(PLANE, 3),'
        if [[ $p_isrgb -ne 0 ]]; then
        _make '     st(3, (a0(ld(5),ld(6)) + a1(ld(5),ld(6)) + a2(ld(5),ld(6))) / maxv / 15);' # gray
        _make '     st(3, ld(3) + 0.8 * (pow(1 - abs(ld(7) / ld(1)), 0.2) / 2 + 0.5));'
        _make '     st(3, ld(3) * maxv),'
        else
        _make '     ifnot(PLANE,'
        _make '      st(3, a0(ld(5), ld(6)) / maxv / 5);'
        _make '      st(3, ld(3) + 0.8 * (pow(1 - abs(ld(7) / ld(1)), 0.2) / 2 + 0.5));'
        _make '      st(3, ld(3) * maxv),'
        _make '      st(3, midv)' # PLANE 1,2
        _make '     ),'
        fi
        _make '     st(3, a3(ld(5), ld(6)))' # PLANE 3
        _make '    )'
        _make '   )'
        _make '  )'
        _make ' )'
        _make ');'
        [[ -n $o_logprogress ]] && _make 'st(9,floor(time(0)));'
        _make 'ld(3)'
        ;;
    gl_kaleidoscope) # by nwoeanhinnogaehr
        _make "st(1, ${a[0]-1});" # speed
        _make "st(2, ${a[1]-1});" # angle
        _make "st(3, ${a[2]-1.5});" # power
        _make 'st(4, 1 - P);' # progress
        _make 'st(5, X / W - 0.5);' # p.x
        _make 'st(6, 0.5 - Y / H);' # p.y
        _make 'st(1, pow(ld(4), ld(3)) * ld(1));' # t
        _make 'st(3, 0);' # i
        _make 'while(lt(ld(3), 7),'
        _make ' st(5, sin(ld(1)) * st(7, ld(5)) + cos(ld(1)) * ld(6));'
        _make ' st(6, sin(ld(1)) * ld(6) - cos(ld(1)) * ld(7));'
        _make ' st(1, ld(1) + ld(2));'
        _make ' st(5, abs(mod(ld(5), 2) - 1));'
        _make ' st(6, abs(mod(ld(6), 2) - 1));'
        _make ' st(3, ld(3) + 1)'
        _make ');'
        _make 'st(5, ld(5) * W);'
        _make 'st(6, (1 - ld(6)) * H);'
        _make 'st(7, a(ld(5), ld(6)));'
        _make 'st(8, b(ld(5), ld(6)));'
        _make 'st(1, mix(A, B, ld(4)));'
        _make 'st(2, mix(ld(7), ld(8), ld(4)));'
        _make 'st(3, 1 - 2 * abs(P - 0.5));'
        _make 'mix(ld(1), ld(2), ld(3))'
        ;;
    gl_Mosaic) # by Xaychru
        _make "st(1, ${a[0]-2});" # endx
        _make "st(2, ${a[1]--1});" # endy
        _make 'st(5, 1 - 2 * P);' # rpr
        _make 'st(5, abs(3 - ld(5) * ld(5) * 2));' # az
        _make 'st(6, pow(cos(P * PI) / 2 + 0.5, 2));'
        _make 'st(3, (X / W - 0.5) * ld(5) + ld(1) * ld(6) + 0.5);' # rp.x
        _make 'st(4, (0.5 - Y / H) * ld(5) + ld(2) * ld(6) + 0.5);' # rp.y
        _make 'st(5, floor(ld(3)));'
        _make 'st(6, floor(ld(4)));'
        _make 'st(3, ld(3) - ld(5));'
        _make 'st(4, ld(4) - ld(6));'
        _make 'st(1, eq(ld(5), ld(1)) * eq(ld(6), ld(2)));' # onEnd
        _make 'st(2, frand(ld(5), ld(6), 2));'
        _make 'ifnot(ld(1),'
        _make ' st(7, floor(ld(2) * 4) * PI / 2);' # ang
        _make ' st(5, cos(ld(7)));'
        _make ' st(6, sin(ld(7)));'
        _make ' st(7, ld(3) - 0.5);'
        _make ' st(4, ld(4) - 0.5);'
        _make ' st(3, 0.5 + ld(5) * ld(7) + ld(6) * ld(4));'
        _make ' st(4, 0.5 - ld(6) * ld(7) + ld(5) * ld(4))'
        _make ');'
        _make 'st(3, ld(3) * W);'
        _make 'st(4, (1 - ld(4)) * H);'
        _make 'if(ld(1) + gt(ld(2), 0.5),'
        _make ' b(ld(3), ld(4)),'
        _make ' a(ld(3), ld(4))'
        _make ')'
        ;;
#   gl_multiply_blend) # by Fernando Kuteken
#       _make 'st(1, A * B / maxv);'
#       _make 'st(2, 2 * (1 - P));'
#       _make 'if(gt(P, 0.5),'
#       _make ' mix(A, ld(1), ld(2)),'
#       _make ' st(2, ld(2) - 1); mix(ld(1), B, ld(2))'
#       _make ')'
#       ;;
    gl_perlin) # by Rich Harris
        _make "st(1, ${a[0]-4});" # scale
        _make "st(2, ${a[1]-0.01});" # smoothness
        _make 'st(3, X / W * ld(1));' # st.x
        _make 'st(4, (1 - Y / H) * ld(1));' # st.y
        _make 'st(5, floor(ld(3)));' # i.x
        _make 'st(6, floor(ld(4)));' # i.y
        _make 'st(3, ld(3) - ld(5));' # f.x
        _make 'st(4, ld(4) - ld(6));' # f.y
        _make 'st(3, ld(3) * ld(3) * (3 - 2 * ld(3)));' # u.x
        _make 'st(4, ld(4) * ld(4) * (3 - 2 * ld(4)));' # u.y
        _make 'st(1, frand(ld(5), ld(6), 1));' # a
        _make 'st(5, ld(5) + 1);'
        _make 'st(7, frand(ld(5), ld(6), 7));' # b
        _make 'st(6, ld(6) + 1);'
        _make 'st(8, frand(ld(5), ld(6), 8));' # d
        _make 'st(5, ld(5) - 1);'
        _make 'st(5, frand(ld(5), ld(6), 5));' # c
        _make 'st(4, mix(ld(1), ld(7), ld(3)) + (ld(5) - ld(1)) * ld(4) * (1 - ld(3)) + (ld(8) - ld(7)) * ld(3) * ld(4));' # n
        _make 'st(1, 1 - P);' # progress
        _make 'st(3, 1 + ld(2));'
        _make 'st(1, mix(-ld(2), ld(3), ld(1)));' # p
        _make 'st(3, ld(1) + ld(2));' # higher
        _make 'st(2, ld(1) - ld(2));' # lower
        _make 'st(1, 1 - smoothstep(ld(2), ld(3), ld(4), 1));' # 1 - q
        _make 'mix(A, B, ld(1))'
        ;;
    gl_pinwheel) # by Mr Speaker
        _make "st(1, ${a[0]-2});" # speed
        _make 'st(2, 1 - P);' # progress
        _make 'st(1, atan2(0.5 - Y / H, X / W - 0.5) + ld(2) * ld(1));' # circPos
        _make 'st(1, mod(ld(1), PI / 4));' # modPos
        _make 'st(1, sgn(ld(2) - ld(1)));' # signed
        _make 'if(step(ld(1), 0.5), A, B)'
        ;;
    gl_polar_function) # by Fernando Kuteken
        _make "st(1, ${a[0]-5});" # segments
        _make 'st(2, X / W - 0.5);'
        _make 'st(3, 0.5 - Y / H);'
        _make 'st(4, atan2(ld(3), ld(2)) - PI / 2);' # angle
        _make 'st(4, cos(ld(1) * ld(4)) / 4 + 1);' # radius
        _make 'st(1, hypot(ld(2), ld(3)));' # difference
        _make 'if(gt(ld(1), ld(4) * (1 - P)), A, B)'
        ;;
    gl_PolkaDotsCurtain) # by bobylito
        _make "st(1, ${a[0]-20});" # dots
        _make "st(2, ${a[1]-0});" # centre.x
        _make "st(3, ${a[2]-0});" # centre.y
        _make 'st(4, X / W * ld(1));'
        _make 'st(4, fract(ld(4)));'
        _make 'st(5, (1 - Y / H) * ld(1));'
        _make 'st(5, fract(ld(5)));'
        _make 'st(1, hypot(ld(4) - 0.5, ld(5) - 0.5));'
        _make 'st(2, (1 - P) / hypot(X / W - ld(2), 1 - Y / H - ld(3)));'
        _make 'if(lt(ld(1), ld(2)), B, A)'
        ;;
    gl_powerKaleido) # by Boundless
        _make "st(1, ${a[0]-2});" # scale
        _make "st(2, ${a[1]-1.5});" # z
        _make "st(3, ${a[2]-5});" # speed
        _make 'st(1, ld(1) / 10);' # dist
        _make 'st(3, ld(3) * (1 - P));'
        _make 'st(4, (X / W - 0.5) * W / H * ld(2));' # uv.x
        _make 'st(5, (0.5 - Y / H) * ld(2));' # uv.y
        _make 'st(6, sin(ld(3)));' # rot s
        _make 'st(7, cos(ld(3)));' # rot c
        _make 'st(4, ld(7) * st(2, ld(4)) + ld(6) * ld(5));'
        _make 'st(5, -ld(6) * ld(2) + ld(7) * ld(5));'
        _make 'st(8, 0);' # iter
        _make 'while(lt(ld(8), 10),'
        _make ' st(2, 0);' # i
        _make ' while(lt(ld(2), 2 * PI),'
        _make '  st(6, sin(ld(2)));'
        _make '  st(7, cos(ld(2)));'
        _make '  if(eq('
        _make '    gt(asin(ld(7)), 0),' # ts
        _make '    gt(ld(5) - ld(1) * ld(7), ld(6) / ld(7) * (ld(4) + ld(1) * ld(6)))'
        _make '   ),'
        _make '   st(4, ld(4) + ld(6) * ld(1) * 2);'
        _make '   st(5, ld(5) - ld(7) * ld(1) * 2);'
        _make '   st(9, dot(ld(4), ld(5), ld(7), ld(6)));'
        _make '   st(4, 2 * ld(7) * ld(9) - ld(4));'
        _make '   st(5, 2 * ld(6) * ld(9) - ld(5))'
        _make '  );'
        _make '  st(2, ld(2) + 120 / 180 * PI)' # change 120 to get different mirror effects
        _make ' );'
        _make ' st(8, ld(8) + 1)'
        _make ');'
        _make 'st(6, sin(-ld(3)));'
        _make 'st(7, cos(-ld(3)));'
        _make 'st(4, ld(7) * st(2, ld(4)) + ld(6) * ld(5));'
        _make 'st(5, -ld(6) * ld(2) + ld(7) * ld(5));'
        _make 'st(4, ld(4) / W * H);'
        _make 'st(4, (ld(4) + 0.5) / 2);'
        _make 'st(5, (ld(5) + 0.5) / 2);'
        _make 'st(4, 2 * abs(ld(4) - floor(ld(4) + 0.5)));'
        _make 'st(5, 2 * abs(ld(5) - floor(ld(5) + 0.5)));'
        _make 'st(1, X / W);' # uv0.x
        _make 'st(2, 1 - Y / H);' # uv0.y
        _make 'st(3, cos(P * PI * 2) / 2 + 0.5);'
        _make 'st(4, mix(ld(4), ld(1), ld(3)));' # uvMix.x
        _make 'st(5, mix(ld(5), ld(2), ld(3)));' # uvMix.y
        _make 'st(4, ld(4) * W);'
        _make 'st(5, (1 - ld(5)) * H);'
        _make 'st(1, a(ld(4), ld(5)));'
        _make 'st(2, b(ld(4), ld(5)));'
        _make 'st(3, cos(P * PI) / 2 + 0.5);'
        [[ -n $o_logprogress ]] && _make 'st(9,floor(time(0)));'
        _make 'mix(ld(1), ld(2), ld(3))'
        ;;
    gl_randomNoisex) # by towrabbit
        _make 'st(1, frand(X, Y, 1));'
        _make 'st(1, floor(ld(1) + (1 - P)));'
        _make 'mix(A, B, ld(1))'
        ;;
    gl_randomsquares) # by gre
        _make "st(1, ${a[0]-10});" # size.x
        _make "st(2, ${a[1]-10});" # size.y
        _make "st(3, ${a[2]-0.5});" # smoothness
        _make 'st(1, floor(ld(1) * X / W));'
        _make 'st(2, floor(ld(2) * (1 - Y / H)));'
        _make 'st(4, frand(ld(1), ld(2), 4));' # r (frand(...) == fract(sin(dot(... algorithm)
        _make 'st(4, ld(4) - ((1 - P) * (1 + ld(3))));'
        _make 'st(4, smoothstep(0, -ld(3), ld(4), 4));' # m
        _make 'mix(A, B, ld(4))'
        ;;
    gl_ripple) # by gre
        _make "st(1, ${a[0]-100});" # amplitude
        _make "st(2, ${a[1]-50});" # speed
        _make 'st(3, X / W - 0.5);' # dir.x
        _make 'st(4, 0.5 - Y / H);' # dir.y
        _make 'st(5, hypot(ld(3), ld(4)));' # dist
        _make 'st(6, 1 - P);' # progress
        _make 'st(5, (sin(ld(6) * (ld(5) * ld(1) - ld(2))) + 0.5) / 30);'
        _make 'st(3, ld(3) * ld(5));' # offset.x
        _make 'st(4, ld(4) * ld(5));' # offset.y
        _make 'st(3, (X / W + ld(3)) * W);'
        _make 'st(4, (1 - ((1 - Y / H) + ld(4))) * H);'
        _make 'st(1, a(ld(3), ld(4)));'
        _make 'st(2, smoothstep(0.2, 1, ld(6), 2));'
        _make 'mix(ld(1), B, ld(2))'
        ;;
    gl_Rolls) # by Mark Craig
        _make "st(1, ${a[0]-0});" # type
        _make "st(2, ${a[1]-0});" # RotDown
        _make 'st(3, PI / 2 * (1 - P));' # theta
        _make 'if(eq(gte(ld(1), 2), ld(2)), st(3, -ld(3)));'
        _make 'st(6, cos(ld(3)));' # c1
        _make 'st(7, sin(ld(3)));' # s1
        _make 'st(4, X / W);' # uvi.x
        _make 'st(5, 1 - Y / H);' # uvi.y
        _make 'ifnot(between(ld(1), 1, 2), st(4, 1 - ld(4)));'
        _make 'if(gte(ld(1), 2), st(5, 1 - ld(5)));'
        _make 'st(8, W / H);' # ratio
        _make 'st(2, ld(4) * ld(8) * ld(6) - ld(5) * ld(7));' # uv2.x
        _make 'st(3, ld(4) * ld(8) * ld(7) + ld(5) * ld(6));' # uv2.y
        _make 'if(between(ld(2), 0, ld(8)) * between(ld(3), 0, 1),'
        _make ' st(2, ld(2) / ld(8));'
        _make ' ifnot(between(ld(1), 1, 2), st(2, 1 - ld(2)));'
        _make ' if(gte(ld(1), 2), st(3, 1 - ld(3)));'
        _make ' st(2, ld(2) * W);'
        _make ' st(3, (1 - ld(3)) * H);'
        _make ' a(ld(2), ld(3)),'
        _make ' B'
        _make ')'
        ;;
    gl_RotateScaleVanish) # by Mark Craig
        _make "st(1, ${a[0]-1});" # FadeInSecond
        _make "st(2, ${a[1]-0});" # ReverseEffect
        _make "st(3, ${a[2]-0});" # ReverseRotation
        _make 'st(0, if(ld(2), P, 1 - P));' # t
        _make 'st(4, (X / W - 0.5) * W / H);' # xc1
        _make 'st(5, 0.5 - Y / H);' # yc1
        _make 'st(3, if(ld(3), 2, -2) * PI * ld(0));' # theta
        _make 'st(6, sin(ld(3)));' # c1
        _make 'st(7, cos(ld(3)));' # s1
        _make 'st(8, max(0.00001, 1 - ld(0)));' # rad
        _make 'st(3, (ld(4) * ld(7) - ld(5) * ld(6)) / ld(8));' # xc2
        _make 'st(4, (ld(4) * ld(6) + ld(5) * ld(7)) / ld(8));' # yc2
        _make 'st(3, ld(3) + W / H / 2);' # uv2.x
        _make 'st(4, ld(4) + 0.5);' # uv2.y
        _make 'st(5, if(ld(2), A, B));' # ColorTo
        _make 'if(between(ld(3), 0, W / H) * between(ld(4), 0, 1),'
        _make ' st(3, ld(3) * H);'
        _make ' st(4, (1 - ld(4)) * H);'
        _make ' st(2, if(ld(2),' # col3
        _make '  b(ld(3), ld(4)),'
        _make '  a(ld(3), ld(4))'
        _make ' )),'
        _make ' st(2, if(ld(1),' # col3
        _make "  st(2, ${a[3]-0});" # backWhite
        _make '  mono(ld(2)),'
        _make '  ld(5))'
        _make ' )'
        _make ');'
        _make 'mix(ld(2), ld(5), ld(0))'
        ;;
    gl_rotateTransition) # by haiyoucuv
        _make 'st(1, X / W - 0.5);'
        _make 'st(2, 0.5 - Y / H);'
        _make 'st(3, 1 - P);' # progress
        _make 'st(5, ld(3) * PI * 2);' # angle
        _make 'st(4, sin(ld(5)));'
        _make 'st(5, cos(ld(5)));'
        _make 'st(6, ld(1) * ld(5) - ld(2) * ld(4) + 0.5);'
        _make 'st(5, ld(1) * ld(4) + ld(2) * ld(5) + 0.5);'
        _make 'st(4, fract(ld(6)));' # p.x
        _make 'st(5, fract(ld(5)));' # p.y
        _make 'st(4, ld(4) * W);'
        _make 'st(5, (1 - ld(5)) * H);'
        _make 'st(1, a(ld(4), ld(5)));'
        _make 'st(2, b(ld(4), ld(5)));'
        _make 'mix(ld(1), ld(2), ld(3))'
        ;;
    gl_rotate_scale_fade) # by Fernando Kuteken
        _make "st(1, ${a[0]-0.5});" # centre.x
        _make "st(2, ${a[1]-0.5});" # centre.y
        _make "st(3, ${a[2]-1});" # rotations
        _make "st(4, ${a[3]-8});" # scale
        _make 'st(5, X / W - ld(1));' # difference.x
        _make 'st(6, (1 - Y / H) - ld(2));' # difference.y
        _make 'st(7, hypot(ld(5), ld(6)));' # dist
        _make 'st(5, ld(5) / ld(7));' # dir.x
        _make 'st(6, ld(6) / ld(7));' # dir.y
        _make 'st(3, 2 * PI * ld(3) * (1 - P));' # angle
        _make 'st(8, 2 * abs(P - 0.5));'
        _make 'st(8, mix(ld(4), 1, ld(8)));' # currentScale
        _make 'st(4, ld(5) * cos(ld(3)) - ld(6) * sin(ld(3)));' # rotatedDir.x
        _make 'st(6, ld(5) * sin(ld(3)) + ld(6) * cos(ld(3)));' # rotatedDir.y
        _make 'st(1, ld(1) + ld(4) * ld(7) / ld(8));' # rotatedUv.x
        _make 'st(2, ld(2) + ld(6) * ld(7) / ld(8));' # rotatedUv.y
        _make 'if(between(ld(1), 0, 1) * between(ld(2), 0, 1),'
        _make ' st(1, ld(1) * W);'
        _make ' st(2, (1 - ld(2)) * H);'
        _make ' st(3, a(ld(1), ld(2)));'
        _make ' st(4, b(ld(1), ld(2)));'
        _make ' st(5, 1 - P);'
        _make ' mix(ld(3), ld(4), ld(5)),'
        _make " st(1, ${a[4]-0.15});" # backGray
        _make ' grey(ld(1))'
        _make ')'
        ;;
    gl_Slides) # by Mark Craig
        _make "st(1, ${a[0]-0});" # type
        _make "st(2, ${a[1]-0});" # In
        _make 'st(5, st(4, 1 - st(3, if(ld(2), 1 - P, P))) / 2);' # rad 1-rad (1-rad)/2
        _make 'ifnot(ld(1), st(6, ld(5)); st(7, 0),' # xc1 yc1
        _make ' if(eq(ld(1), 1), st(6, ld(4)); st(7, ld(5)),'
        _make '  if(eq(ld(1), 2), st(6, ld(5)); st(7, ld(4)),'
        _make '   if(eq(ld(1), 3), st(6, 0); st(7, ld(5)),'
        _make '    if(eq(ld(1), 4), st(6, ld(4)); st(7, 0),'
        _make '     if(eq(ld(1), 5), st(6, st(7, ld(4))),'
        _make '      if(eq(ld(1), 6), st(6, 0); st(7, ld(4)),'
        _make '       if(eq(ld(1), 7), st(6, st(7, 0)),'
        _make '        st(6, st(7, ld(5)))' # default centre
        _make '))))))));'
        _make 'st(4, X / W);'
        _make 'st(5, Y / H);'
        _make 'if(between(ld(4), ld(6), ld(6) + ld(3)) * between(ld(5), ld(7), ld(7) + ld(3)),'
        _make ' st(4, (ld(4) - ld(6)) / ld(3) * W);'
        _make ' st(5, (ld(5) - ld(7)) / ld(3) * H);'
        _make ' if(ld(2),'
        _make '  b(ld(4), ld(5)),'
        _make '  a(ld(4), ld(5))'
        _make ' ),'
        _make ' if(ld(2), A, B)'
        _make ')'
        ;;
    gl_squareswire) # by gre
        _make "st(1, ${a[0]-10});" # squares.h
        _make "st(2, ${a[1]-10});" # squares.v
        _make "st(3, ${a[2]-1.0});" # direction.x
        _make "st(4, ${a[3]--0.5});" # direction.y
        _make "st(5, ${a[4]-1.6});" # smoothness
        _make 'st(6, hypot(ld(3), ld(4)));'
        _make 'st(3, ld(3) / ld(6));' # v.x
        _make 'st(4, ld(4) / ld(6));' # v.y
        _make 'st(6, abs(ld(3) + abs(ld(4))));'
        _make 'st(3, ld(3) / ld(6));'
        _make 'st(4, ld(4) / ld(6));'
        _make 'st(6, ld(3) / 2 + ld(4) / 2);' # d
        _make 'st(6, ld(3) * X / W + ld(4) * (1 - Y / H) - (ld(6) - 0.5 + (1 - P) * (1 + ld(5))));'
        _make 'st(6, smoothstep(-ld(5), 0, ld(6), 6));' # pr
        _make 'st(1, X / W * ld(1));'
        _make 'st(2, (1 - Y / H) * ld(2));'
        _make 'st(1, fract(ld(1)));' # squarep.x
        _make 'st(2, fract(ld(2)));' # squarep.y
        _make 'st(5, ld(6) / 2);' # squaremin
        _make 'st(6, 1 - ld(5));' # squaremax
        _make 'if(step(ld(5), ld(1)) * step(ld(5), ld(2)) * step(ld(1), ld(6)) * step(ld(2), ld(6)), B, A)'
        ;;
    gl_static_wipe) # by Ben Lucas
        _make "st(1, ${a[0]-1});" # transitionUpToDown
        _make "st(2, ${a[1]-0.5});" # max_static_span
        _make 'st(3, 1 - P);' # progress
        _make 'st(2, ld(2) * sqrt(sin(PI * ld(3))));' # span
        _make 'st(4, X / W);' # uv.x
        _make 'st(5, 1 - Y / H);' # uv.y
        _make 'st(1, if(ld(1), 1 - ld(5), ld(5)));' # transitionEdge
        _make 'st(6, ld(3) - ld(2));'
        _make 'st(6, smoothstep(ld(6), ld(3), ld(1), 6));'
        _make 'st(7, ld(3) + ld(2));'
        _make 'st(7, smoothstep(ld(3), ld(7), ld(1), 7));'
        _make 'st(6, ld(6) * (1 - ld(7)));' # noiseEnvelope
        _make 'st(7, if(1 - step(ld(3), ld(1)), B, A));' # transitionMix
        if [[ $p_isrgb -ne 0 ]]; then
        _make 'if(lt(PLANE, 3),'
        else
        _make 'if(not(PLANE),'
        fi
        _make ' st(4, ld(4) * (1 + ld(3)));'
        _make ' st(5, ld(5) * (1 + ld(3)));'
        _make ' st(1, frand(ld(4), ld(5), 1));' # (using frand not rnd)
        _make ' st(1, ld(1) * maxv),' # noise
        if [[ $p_isrgb -ne 0 ]]; then
        _make ' st(1, maxv)'
        else
        _make ' st(1, if(lt(PLANE, 3), midv, maxv))'
        fi
        _make ');'
        _make 'mix(ld(7), ld(1), ld(6))'
        ;;
    gl_swap) # by gre
        _make "st(1, ${a[0]-0.4});" # reflection
        _make "st(2, ${a[1]-0.2});" # perspective
        _make "st(3, ${a[2]-3});" # depth
        _make "st(4, ${a[3]-0});" # backWhite
        _make 'st(0, 1 - P);' # progress
        _make 'st(7, mix(1, ld(3), ld(0)));' # size
        _make 'st(8, ld(2) * ld(0));' # persp
        _make 'st(5, X / W * ld(7) / (1 - ld(8)));' # pfr.x
        _make 'st(6, (0.5 - Y / H) * ld(7) / (1 - ld(7) * ld(8) * X / W) + 0.5);' # pfr.y
        _make 'st(0, 1 - ld(0));'
        _make 'st(7, mix(1, ld(3), ld(0)));' # size
        _make 'st(8, ld(2) - ld(8));' # persp
        _make 'st(2, (X / W - 1) * ld(7) / (1 - ld(8)) + 1);' # pto.x
        _make 'st(3, (0.5 - Y / H) * ld(7) / (1 - ld(7) * ld(8) * (0.5 - X / W)) + 0.5);' # pto.y
        _make 'st(7, between(ld(2), 0, 1) * between(ld(3), 0, 1));' # inBounds(pto)
        _make 'st(8, between(ld(5), 0, 1) * between(ld(6), 0, 1));' # inBounds(pfr)
        _make 'st(0, gt(ld(0), 0.5));'
        _make 'ifnot(st(0, if(ld(8) * (ld(0) + not(ld(7))), -1, if(ld(7) * not(ld(0) * ld(8)), 1, 0))),'
        _make ' st(3, ld(3) * -1.2 - 0.02);'
        _make ' ifnot(st(0, 2 * between(ld(2), 0, 1) * between(ld(3), 0, 1)),'
        _make '  st(6, ld(6) * -1.2 - 0.02);'
        _make '  st(0, -2 * between(ld(5), 0, 1) * between(ld(6), 0, 1))'
        _make ' )'
        _make ');'
        _make 'if(ld(0),'
        _make ' if(lt(ld(0), 0), st(2, ld(5)); st(3, ld(6)));'
        _make ' st(5, ld(2) * W);'
        _make ' st(6, (1 - ld(3)) * H);'
        _make ' if(lt(ld(0), 0),'
        _make '  st(2, a(ld(5), ld(6))),'
        _make '  st(2, b(ld(5), ld(6)))'
        _make ' );'
        _make ' if(eq(abs(ld(0)), 2),'
        _make '  st(1, ld(1) * (1 - ld(3)));'
        _make '  st(4, mono(ld(4)));'
        _make '  mix(ld(4), ld(2), ld(1)),'
        _make '  ld(2)'
        _make ' ),'
        _make ' mono(ld(4))'
        _make ')'
        ;;
    gl_Swirl) # by Sergey Kosarevsky
        _make 'st(1, 1);' # Radius
        _make 'st(2, 1 - P);' # T
        _make 'st(3, X / W - 0.5);' # UV.x
        _make 'st(4, 0.5 - Y / H);' # UV.y
        _make 'st(5, hypot(ld(3), ld(4)));' # Dist
        _make 'if(lt(ld(5), ld(1)),'
        _make ' st(1, (ld(1) - ld(5)) / ld(1));' # Percent
        _make ' st(5, if(lte(ld(2), 0.5), ld(2), 1 - ld(2)) * 2);' # A
        _make ' st(1, ld(1) * ld(1) * ld(5) * 8 * PI);' # Theta
        _make ' st(5, sin(ld(1)));' # S
        _make ' st(6, cos(ld(1)));' # C
        _make ' st(1, dot(ld(3), ld(4), ld(6), -ld(5)));'
        _make ' st(4, dot(ld(3), ld(4), ld(5), ld(6)));' # UV.y
        _make ' st(3, ld(1))' # UV.x
        _make ');'
        _make 'st(3, (ld(3) + 0.5) * W);' # UV.x
        _make 'st(4, (0.5 - ld(4)) * H);' # UV.y
        _make 'st(5, a(ld(3), ld(4)));' # C0
        _make 'st(6, b(ld(3), ld(4)));' # C1
        _make 'mix(ld(5), ld(6), ld(2))'
        ;;
    gl_WaterDrop) # by Paweł Płóciennik
        _make "st(1, ${a[0]-30});" # amplitude
        _make "st(2, ${a[1]-30});" # speed
        _make 'st(3, 1 - P);' # progress
        _make 'st(4, X / W - 0.5);' # dir.x
        _make 'st(5, 0.5 - Y / H);' # dir.y
        _make 'st(6, hypot(ld(4), ld(5)));' # dist
        _make 'st(7, if(lte(ld(6), ld(3)),'
        _make ' st(1, sin(ld(6) * ld(1) - ld(3) * ld(2)));'
        _make ' st(4, ld(4) * ld(1));' # offset.x
        _make ' st(5, ld(5) * ld(1));' # offset.y
        _make ' st(4, X + ld(4) * W);'
        _make ' st(5, Y - ld(5) * H);'
        _make ' a(ld(4), ld(5)),'
        _make ' A'
        _make '));'
        _make 'mix(ld(7), B, ld(3))'
        ;;
    esac
    x=$made
    echo "$x"
}

# custom expressions for supplementary transitions
_st_transition() { # transition args
    local x # expr
    local a=(${2//,/ }) # args
    _make ''
#   case $1 in
#   x_screen_blend) # modelled on gl_multiply_blend
#       _make 'st(1, (1 - (1 - A / maxv) * (1 - B / maxv)) * maxv);'
#       _make 'st(2, 2 * (1 - P));'
#       _make 'if(gt(P, 0.5),'
#       _make ' mix(A, ld(1), ld(2)),'
#       _make ' st(2, ld(2) - 1); mix(ld(1), B, ld(2))'
#       _make ')'
#       ;;
#   x_overlay_blend) # modelled on gl_multiply_blend
#       _make 'st(1, if(lte(A, midv),'
#       _make ' 2 * A * B / maxv,'
#       _make ' (1 - 2 * (1 - A / maxv) * (1 - B / maxv)) * maxv'
#       _make '));'
#       _make 'st(2, 2 * (1 - P));'
#       _make 'if(gt(P, 0.5),'
#       _make ' mix(A, ld(1), ld(2)),'
#       _make ' st(2, ld(2) - 1); mix(ld(1), B, ld(2))'
#       _make ')'
#       ;;
#   x_step) # no transition, steps at halfway point
#       x='if(gt(P, 0.5), A, B)'
#       ;;
#   esac
    x=$made
    echo "$x"
}

# get transition expression
_transition() { # transition
    local x=$(_xf_transition $1 $2) # try Xfade
    [[ -n $x ]] && is_xf=true
    [[ -z $x ]] && x=$(_gl_transition $1 $2) # try GL
    [[ -z $x ]] && x=$(_st_transition $1 $2) # try supplementary
    [[ -z $x ]] && exit $ERROR # unknown transition name
    local s r
    for s in rem mix fract smoothstep frand a b mono grey dot step; do # expand pseudo functions
        while [[ $x =~ $s\( ]]; do
            r=$(_heredoc FUNC | gawk -v e="$x" -v f=$s -f-)
            x=${r%%|*} # search
            r=${r#*|} # args
            [[ $s == mix && -n $is_xf ]] && r+=' xf' # xfade mix args are different
            r=$(_$s $r) # replace
            x=${x/@/$r} # expand
        done
    done
    for s in black white maxv midv; do # expand pseudo variables
        r=p_$s # replace
        x=${x//$s/${!r}} # expand
    done
    echo "$x"
    exit 0
}

# output custom expression
_expr() { # path expr
    local path=$(_expand "$1")
    local expr=$(_expand "$2")
    if [[ $path == - ]]; then
        echo "$expr"
    elif [[ -n $o_xappend ]]; then
        echo "$expr" >> $path
    else
        echo "$expr" > $path
    fi
}

# output easing plot
_plot() { # path easing
    local path=$(_expand "$1")
    local ll=24 # log level = warning
    local expr mode
    for mode in in out inout; do
        expr=$(_easing $2 $mode)
        expr="$expr; ifnot(PLANE+X+Y,print(-1,$ll);print(1-P,$ll);print(1-ld(0),$ll))"
        expr=$(_expand '%x' "$expr")
        local log=$TMP-plot-$mode.log
        export FFREPORT="file=$log:level=$ll" # prints to log file
        ffmpeg -hide_banner -loglevel level+repeat+error -filter_complex_threads 1 \
            -f lavfi -i "color=c=black:s=1x1:r=100:d=3,format=gray" \
            -f lavfi -i "color=c=white:s=1x1:r=100:d=3,format=gray" \
            -filter_complex "[0][1]xfade=duration=1:offset=1:transition=custom:expr='$expr'" -f null -
    done
    unset FFREPORT # prevent further logging
    local size=$(_size ${o_psize-$PLOTSIZE} $PLOTSIZE)
    local plt=$TMP-plot.plt # gnuplot script
    _heredoc PLOT | gawk -v title=$2 -v size=$size -v h=${PLOTSIZE#*x} -v output="$path" -v RS="[$N$R]" -f- $TMP-plot-*.log > $plt
    gnuplot $plt
}

# output demo video
_video() { # path
    local path=$(_expand "$1") file enc
    shift
    local inputs=("$@")
    local n=${#inputs[@]} m i j
    if [[ $n -lt 2 ]]; then
        n=2
        inputs=(sheep goat)
        for i in 0 1; do
            file=$TMP-${inputs[i]}.png
            _heredoc ${inputs[i]^^} | base64 -D -o $file
            inputs[$i]=$file
        done
    fi
    m=$((n-1))
    local duration=${o_vtduration-$VIDEOTRANSITIONDURATION} time=${o_vtime-$VIDEOTIME} length=$o_vlength err offset
    if [[ -n $o_vtime && -n $o_vlength ]]; then
        duration=$(_calc "($length - $n * $time) / $m")
        [[ $duration =~ ^- ]] && err="calculated duration = $duration, using 0" && duration=0 && length=
    elif [[ -n $o_vlength ]]; then
        time=$(_calc "($length - $m * $duration) / $n")
        [[ $time =~ ^- ]] && err="calculated time = $time, using 0" && time=0 && length=
    fi
    [[ -z $length ]] && length=$(_calc "$n * $time + $m * $duration")
    [[ -n $err ]] && _error "$err, adjusted length = $length"
    local expr=$(_expand '%n%X')
    local fps=${o_vfps-$VIDEOFPS}
    [[ $path =~ .gif && $fps -gt 50 ]] && fps=50 # max for browser support
    local dims=$(_dims ${inputs[0]})
    local size=$(_size ${o_vsize-$dims} $dims 1) # even
    local width=${size%x*} height=${size#*x}
    local fsmult=${o_vfsmult-$VIDEOFSMULT}
    local bb=$(_calc "int(3 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled boxborder
    local fs=$(_calc "int(16 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled fontsize
    local drawtext="drawtext=x='(w-text_w)/2':y='(h-text_h)/2':box=1:boxborderw=$bb:text_align=C:fontsize=$fs:text='TEXT'"
    local text1=$transition text2=$transition
    [[ -n $args ]] && text1+=$(_expand '=%A') && text2+=$(_expand '=%a')
    [[ $easing != linear ]] && text1+=$(_expand '%nno easing') && text2+=$(_expand '%n%e-%m')
    readarray -d , -n 4 -t d <<<$VIDEOSTACK, # defaults
    readarray -d , -n 4 -t o <<<$o_vstack,,,, # options
    local stack=${o[0]:-${d[0]}} gap=${o[1]:-${d[1]}} fill=${o[2]:-${d[2]}} pad=${o[3]:-${d[3]}}
    local script=$TMP-script.txt # filter_complex_script
    rm -f $script
    for i in $(seq 0 1 $m); do
        local start=$duration stop=$(_calc "($time + $duration + 1 / $fps)")
        [[ $i -eq 0 ]] && start=0
        [[ $i -eq $m ]] && stop=$(_calc "$stop - $duration")
        cat << EOT >> $script
movie='${inputs[i]}',
format=pix_fmts=$format,
scale=width=$width:height=$height:flags=lanczos,
loop=loop=1:size=1,
fps=fps=$fps,
tpad=start_mode=clone:start_duration=$start:stop_mode=clone:stop_duration=$stop
[v$i];
EOT
    done
    # alt: testsrc=size=$size:rate=$fps:duration=$duration:decimals=3
    #      testsrc2=size=$size:rate=$fps:duration=$duration
    if [[ -z $stack || $stack == 1 || ( $easing == linear && -z $o_easing && -z $args ) ]]; then # unstacked
        if [[ -n $o_vname ]]; then
            for i in $(seq 0 1 $m); do
                echo "[v$i]${drawtext/TEXT/$text2}[v$i];" >> $script
            done
        fi
        echo "[v0]null[v];" >> $script
        for j in $(seq $m); do
            i=$((j-1))
            offset=$(_calc "$j * $time + $i * $duration")
            echo "[v][v$j]xfade=offset=$offset:duration=$duration:transition=custom:expr='$expr'[v];" >> $script
        done
    else # stacked
        [[ $stack == a ]] && stack=v && [[ $transition =~ (up|down|vu|vd|squeezeh|horz) ]] && stack=h
        local cell2="$gap+w0_0"
        [[ $stack == v ]] && cell2="0_h0+$gap"
        local expr0=$transition # xfade transition
        if [[ $transition =~ _ ]]; then # custom transition
            expr0=$(_transition $transition)
            expr0=$(_expand "%n%X" "$expr0")
            expr0="custom:expr='$expr0'" # default args
        fi
        for i in $(seq 0 1 $m); do
            echo "[v$i]split[v${i}a][v${i}b];" >> $script
        done
        if [[ -n $o_vname ]]; then
            for i in $(seq 0 1 $m); do
                echo "[v${i}a]${drawtext/TEXT/$text1}[v${i}a];" >> $script
                echo "[v${i}b]${drawtext/TEXT/$text2}[v${i}b];" >> $script
            done
        fi
        echo "[v0a]null[va];" >> $script
        echo "[v0b]null[vb];" >> $script
        for j in $(seq $m); do
            i=$((j-1))
            offset=$(_calc "$j * $time + $i * $duration")
            echo "[va][v${j}a]xfade=offset=$offset:duration=$duration:transition=$expr0[va];" >> $script
            echo "[vb][v${j}b]xfade=offset=$offset:duration=$duration:transition=custom:expr='$expr'[vb];" >> $script
        done
        echo "[va][vb]xstack=inputs=2:fill=$fill:layout=0_0|$cell2[v];" >> $script
    fi
    if [[ $pad -gt 0 ]]; then
        echo "[v]pad=x=$pad:y=$pad:w=iw+$pad*2:h=ih+$pad*2:color=$fill[v];" >> $script
    fi
    if [[ $path == /dev/null ]]; then # no output
        enc='-f null'
    elif [[ $path =~ .gif ]]; then # animated for .md
        echo '[v]split[s0][s1]; [s0]palettegen[s0]; [s1][s0]paletteuse[v]' >> $script
    elif [[ $path =~ .mkv ]]; then # lossless - see https://trac.ffmpeg.org/wiki/Encode/FFV1
        enc="-c:v ffv1 -level 3 -coder 1 -context 1 -g 1 -pix_fmt yuv420p -r $fps"
    else # x264 - see https://trac.ffmpeg.org/wiki/Encode/H.264
        enc="-c:v libx264 -preset medium -tune stillimage -pix_fmt yuv420p -r $fps"
    fi
    local ffopts="-y -hide_banner -loglevel ${o_loglevel-warning} -stats_period 1"
    ffmpeg $ffopts -filter_complex_threads 1 -filter_complex_script $script -map [v]:v -an -t $length $enc "$path"
    [[ $path =~ .gif ]] && which -s gifsicle && mv "$path" $TMP-video.gif && gifsicle -O3 -o "$path" $TMP-video.gif
}

_main "$@" # run

exit 0 # heredocs follow

@PIXFMT # parse pix_fmts
/BIT_DEPTHS/ { getline; go = 1}
$2 == format { split($NF, a, "-"); print a[1] }
!PIXFMT

@FUNC # expr pseudo function substitution
BEGIN {
    OFS = "|"
    if (i = index(e, f "(")) {
        s = substr(e, i)
        while (s ~ /^[^(]*\([^()]*\(/ && sub(/\([^()]*\)/, "{&}", s)) { # nested (..)
            sub(/\{\(/, "{", s)
            sub(/\)\}/, "}", s)
        }
        s = substr(s, 1, index(s, ")"))
        e = substr(e, 1, i - 1) "@" substr(e, i + length(s))
        gsub(/\{/, "(", s)
        gsub(/\}/, ")", s)
        sub(/^[^(]*\(/, "", s)
        gsub(/, */, " ", s)
        sub(/\)$/, "", s)
    }
    print e, s # expr args
}
!FUNC

@PLOT # gnuplot script
# this assumes 1s transition duration at 100 fps
BEGIN {
    split(size, a, "x")
    fs = 12 * a[1] / h
    blw = lw = 1.5 * a[1] / h
    ext = tolower(output)
    if (ext ~ /\.pdf$/ || ext ~ /\.eps$/) { # inches! (default 5x3.5")
        a[1] /= 96
        a[2] /= 96
        fs *= 1.5
        lw *= 2.5 / 1.5
        if (ext ~ /\.eps$/)
            lw *= 2
    }
    size = a[1] "," a[2]
}
$1 != "[warning]" || $2 !~ /^[-0-9]/ { next } # non-data
$2 ~ /^-1\.0+$/ { # start of data pair
    if (FILENAME != fn) { # new file
        fn = FILENAME
        match(fn, /-([inout]+)\.log$/, a)
        mode = a[1]
    }
    col = "p" # progress
    next
}
$2 ~ /^[-0-9.]+$/ { # data
    if (col == "p")
        p = int($2 * 100 + 0.5) # (always integral anyway)
    else
        val[mode,p] = +$2
    col = "e" # easing
}
END {
    OFS = "\t"
    if (ext ~ /\.gif$/)
        terminal = "gif"
    else if (ext ~ /\.jpe?g$/)
        terminal = "jpeg"
    else if (ext ~ /\.png$/)
        terminal = "pngcairo"
    else if (ext ~ /\.svg$/)
        terminal = "svg"
    else if (ext ~ /\.pdf$/)
        terminal = "pdfcairo"
    else if (ext ~ /\.eps$/)
        terminal = "epscairo"
    else if (ext ~ /\.x?html?$/)
        terminal = "canvas"
    else
        terminal = "unknown"
    printf("set terminal %s size %s\n", terminal, size)
    printf("set termoption enhanced\n")
    printf("set termoption font 'Helvetica,%g'\n", fs)
    printf("set output '%s'\n", output)
    printf("set title '{/Helvetica-Bold*1.4 %s}'\n", title)
    printf("set xlabel '{/Helvetica*1.2 progress}'\n")
    printf("set ylabel '{/Helvetica*1.2 easing}'\n")
    printf("set grid\n")
    printf("set border 3 linewidth %g\n", blw)
    printf("set tics nomirror out\n")
    printf("set object 1 rectangle from screen -1.1,-1.1 to screen 1.1,1.1 fillcolor rgb'#FCFCFC' behind\n")
    printf("set object 2 rect from graph 0, graph 0 to graph 1, graph 1 fillcolor rgb '#E8FFE8' behind\n")
    printf("set key left top\n")
    printf("set style line 1 linewidth %g linecolor rgb 'red'\n", lw)
    printf("set style line 2 linewidth %g linecolor rgb 'green'\n", lw)
    printf("set style line 3 linewidth %g linecolor rgb 'blue'\n", lw)
    print ""
    print "$data << EOD"
    print "progress", "in", "out", "inout"
    for (p = 0; p <= 100; p++)
        print p / 100, val["in",p], val["out",p], val["inout",p]
    print "EOD"
    print ""
    print "plot $data using 'progress':'in' with lines linestyle 1 title 'in', \\"
    print "     $data using 'progress':'out' with lines linestyle 2 title 'out', \\"
    print "     $data using 'progress':'inout' with lines linestyle 3 title 'inout'"
}
!PLOT

@LIST # list transitions & easings filtered from this script for -L option
BEGIN {
    OFS = "\t"
    title["rp"] = "Standard Easings (Robert Penner):"
    title["se"] = "Supplementary Easings:"
    title["xf"] = "Xfade Transitions:"
    title["gl"] = "GL Transitions:"
    title["st"] = "Supplementary Transitions:"
}

$1 ~ /^#/ { next }

match($1, /^_(..)_(transition|easing)\(\)/, a) { # transition/easing func
if(a[1]=="st") next # historic
    go = 1
    if (cases)
        print ""
    print title[a[1]]
}

match($1, /^([A-Za-z_|]+)\)$/, a) && go { # case
    cases = a[1]
    author = args = defs = c = ""
    if (match($0, /# +by +(.*)$/, a)) # author
        author = a[1]
    do {
        getline
        if (match($0, /\$\{a\[[0-9]\]-([^}]+)\}.*# *(.*)/, a)) { # bash substitution
            args = args c a[2] # comment
            defs = defs c a[1] # default
            c = ","
        }
    } while ($1 != ";;")
    n = split(cases, a, "|")
    for (i = 1; i <= n; i++)
        print a[i], args, defs, author
}

$1 ~ /^\}/ { go = 0 }
!LIST

@SHEEP # sheep PNG
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
!SHEEP

@GOAT # goat PNG
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
!GOAT

@USAGE # CLI usage for -H option
FFmpeg Xfade Easing script version $VERSION by Raymond Luckhurst, scriptit.uk
Generates custom xfade expressions for rendering transitions with easing
See https://github.com/scriptituk/xfade-easing
Usage: $CMD [options] [video inputs]
Options:
    -f pixel format (default: $FORMAT): use ffmpeg -pix_fmts for list
    -t transition name (default: $TRANSITION); use -L for list
    -e easing function (default: $EASING); see -L for list
    -m easing mode (default: $MODE): in out inout
    -x expr output filename (default: no expr), accepts expansions, - for stdout
    -a append to expr output file
    -s expr output format string (default: $EXPRFORMAT)
       %t expands to the transition name; %e easing name; %m easing mode
       %T, %E, %M upper case expansions of above
       %a expands to the transition arguments; %A to the default arguments (if any)
       %x expands to the generated expr, condensed, intended for inline filterchains
       %X does too but is not condensed, intended for -filter_complex_script files
       %y expands to the easing expression only, inline; %Y script
       %z expands to the eased transition expression only, inline; %Z script
          for the uneased transition expression only, omit -e option and use %x or %X
       %n inserts a newline
    -p easing plot output filename (default: no plot)
       accepts expansions but %m/%M are pointless as plots show all easing modes
       formats: gif, jpg, png, svg, pdf, eps, html <canvas>, from file extension
    -c canvas size for easing plot (default: $PLOTSIZE, scaled to inches for PDF/EPS)
       format: WxH; omitting W or H keeps aspect ratio, e.g. -z x300 scales W
    -v video output filename (default: no video), accepts expansions
       formats: animated gif, mp4 (x264 yuv420p), mkv (FFV1 lossless), from file extension
       if /dev/null then format is the null muxer (no output)
       if gifsicle is available then gifs will be optimised
    -z video size (default: input 1 size)
       format: WxH; omitting W or H keeps aspect ratio, e.g. -z 300x scales H
    -d video transition duration (default: ${VIDEOTRANSITIONDURATION}s, minimum: 0) (see note after -l)
    -i time between video transitions (default: ${VIDEOTIME}s, minimum: 0) (see note after -l)
    -l video length (default: ${VIDEOLENGTH}s)
       note: options -d, -i, -l are interdependent: l = ni + (n - 1)d for n inputs
       given -t & -l, d is calculated; else given -l, t is calculated; else l is calculated
    -r video framerate (default: ${VIDEOFPS}fps)
    -n show effect name on video as text (requires the libfreetype library)
    -u video text font size multiplier (default: $VIDEOFSMULT)
    -k video stack orientation,gap,colour,padding (default: $VIDEOSTACK), e.g. h,2,red,1
       stacks uneased and eased videos horizontally (h), vertically (v) or auto (a)
       auto selects the orientation that displays easing to best effect
       also stacks transitions with default and custom parameters, eased or not
       videos are only stacked if they are different (nonlinear-eased or customised)
       unstacked videos can be padded using orientation=1, e.g. 1,0,blue,5
    -L list all transitions and easings
    -H show this usage text
    -V show this script version
    -I set ffmpeg loglevel info for -v (default: warning)
    -P log xfade progress percentage using print() (implies -I)
    -T temporary file directory (default: $TMPDIR)
    -K keep temporary files if temporary directory is not $TMPDIR
Notes:
    1. point the shebang path to a bash4 location (defaults to MacPorts install)
    2. this script requires Bash 4 (2009), gawk, gsed, envsubst, ffmpeg, gnuplot, base64
    3. use -filter_complex_threads 1 ffmpeg option (slower!) because xfade expressions
       are not thread-safe (the st() & ld() functions use contextual allocation)
    4. certain xfade transitions are not implemented because they perform aggregation
       (distance, hblur)
    5. many GL Transitions are also ported, some of which take customisation parameters
       to override defaults append parameters as CSV after an = sign,
       e.g. -t gl_PolkaDotsCurtain=10,0.5,0.5 for 10 dots centred
    6. many transitions do not lend themselves well to easing, and easings that overshoot
       (back & elastic) may cause weird effects!
!USAGE
