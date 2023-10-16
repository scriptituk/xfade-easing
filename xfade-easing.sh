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
export VERSION=1.1e
export TMPDIR=/tmp

TMP=$TMPDIR/${CMD%.*}-$$
trap "rm -f $TMP-*" EXIT
ERROR=64 # unreserved exit code
N=$'\n'
T=$'\t'
P='ld(0)' # progress
FFOPTS='-y -hide_banner -loglevel warning -stats_period 1'

# defaults
export FORMAT=rgb24
export TRANSITION=fade
export EASING=linear
export MODE=inout
export EXPRFORMAT="'%x'"
export PLOTSIZE=640x480 # default for gnuplot (4:3)
export VIDEOSIZE=250x200 # sheep/goat png (5:4)
export VIDEOLENGTH=5
export VIDEOTRANSITIONDURATION=3
export VIDEOFPS=25
export VIDEOSTACK=,0,white
export VIDEOFSMULT=1.0

# pixel format
p_max= # maximum value of component
p_mid= # median value of component
p_black= # black value
p_white= # white value

_main() {
    _deps || exit $ERROR # check dependencies
    _opts "$@" || exit $ERROR # get options
    _tmp || exit $ERROR # set tmp dir
    format=${o_format-$FORMAT}
    transition=${o_transition-$TRANSITION}
    [[ $transition =~ = ]] && args=${transition#*=} && transition=${transition%=*}
    easing=${o_easing-$EASING}
    mode=${o_mode-$MODE}
    xformat=${o_xformat-$EXPRFORMAT}

    [[ -n $o_list ]] && _list && exit 0
    [[ -n $o_help ]] && _help && exit 0
    [[ -n $o_version ]] && _version && exit 0

    _format $format || exit $ERROR # set pix format vars

    [[ ! $mode =~ ^(in|out|inout)$ ]] && _error "unknown easing mode '$mode'" && exit $ERROR

    easing_expr=$(_easing $easing $mode) # get easing expr
    [[ -z $easing_expr ]] && _error "unknown easing '$easing'" && exit $ERROR

    transition_expr=$(_transition $transition $args) # get transition expr
    [[ -z $transition_expr ]] && _error "unknown transition '$transition'" && exit $ERROR

    expr=$transition_expr # uneased (linear)
    transition_expr=$(gsed -e "s/\<P\>/$P/g" <<<$transition_expr) # expects eased progress in ld(0)
    if [[ $easing == linear ]]; then
        easing_expr='st(0, P)' # no easing
    else
        expr="$easing_expr%n;%n$transition_expr" # chained easing & transition
    fi

    [[ -n $o_expr ]] && _expr "$o_expr" "$xformat" # output custom expression
    [[ -n $o_plot ]] && _plot "$o_plot" $easing    # output easing plot
    [[ -n $o_video ]] && _video "$o_video" "$o_vinputs" # output demo video
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
    _heredoc LIST | gawk -f- $0 | gawk '{
        if (/:/ || /^$/)
            print
        else
            print "\t" $1 ($2 ? sprintf(" [args: %s; default: =%s]", $2, $3) : "")
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
    while getopts ':f:t:e:m:x:as:p:c:v:i:z:l:d:r:nu:2:LHVT:K' opt; do
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
        i) o_vinputs=$OPTARG ;;
        z) o_vsize=$OPTARG ;;
        l) o_vlength=$OPTARG ;;
        d) o_vtduration=$OPTARG ;;
        r) o_vfps=$OPTARG ;;
        n) o_vname=true ;;
        u) o_vfsmult=$OPTARG ;;
        2) o_vstack=$OPTARG ;;
        L) o_list=true ;;
        H) o_help=true ;;
        V) o_version=true ;;
        T) o_tmp=$OPTARG ;;
        K) o_keep=true ;;
        :) _error 'missing argument'; _help; return $ERROR ;;
        \?) _error 'invalid option'; _help; return $ERROR ;;
        esac
    done
#   shift $(($OPTIND - 1))
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
        x=${x//%n/} && x=${x// /} # compact
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
    _heredoc LIST | gawk -f- $0 | gawk -v transition=$1 '$1 == transition { if ($3) print $3 }'
}

# calculate expression using awk
_calc() { # expr
    gawk -e "BEGIN { ORS = \"\"; print ($1) }"
}

# expression builder
_make() { # expr
    if [[ $# -eq 0 ]]; then
        made=
    elif [[ -z $made ]]; then
        made="$1"
    else
        made+="%n$1"
    fi
}

# C99 % (remainder) operator: a % b = a - (a / b * b) (/ rounds towards 0)
# (not subexpression safe: group first)
_rem() { # a b
    echo "($1 - trunc($1 / $2) * $2)"
}

# vf_xfade.c fract(a)
# (not subexpression safe: group first)
_fract() { # a
    echo "$1 - floor($1)"
}


# vf_xfade.c smoothstep(edge0,edge1,x)
# (not subexpression safe: group first)
_smoothstep() { # edge0 edge1 x st
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
    local e="st($3, sin($1 * 12.9898 + $2 * 78.233) * 43758.545)"
    echo "$e - floor(ld($3))"
}

# get first input value
_a() { # X Y
    echo "if(eq(PLANE,0), a0($1,$2), if(eq(PLANE,1), a1($1,$2), if(eq(PLANE,2), a2($1,$2), a3($1,$2))))"
}

# get second input value
_b() { # X Y
    echo "if(eq(PLANE,0), b0($1,$2), if(eq(PLANE,1), b1($1,$2), if(eq(PLANE,2), b2($1,$2), b3($1,$2))))"
}

# mix linear interpolation
# (not subexpression safe: group first)
_mix() { # a b mix xf
    if [[ -n $4 ]]; then
        echo "$1 * $3 + $2 * (1 - $3)" # xfade mix fn
    else
        echo "$1 * (1 - $3) + $2 * $3"
    fi
}

# dot product
# (not subexpression safe: group first)
_dot() { # x1 y1 x2 y2
    echo "$1 * $3 + $2 * $4"
}

# step function
_step() { # edge x
    echo "gte($2, $1)"
}

# easing functions by Robert Penner (single arg version by Michael Pohoreski, optimised by me)
# see http://robertpenner.com/easing/
# see https://github.com/Michaelangel007/easing
_rp_easing() { # easing mode
    local K=1.70158 # for -10% back
    local K1=2.70158 # K+1
    local H=1.525 # for back in-out
    local H1=2.525 # H+1
    local i o io # mode expressions
    local x # expr
    case $1 in
        # note: P is xfade P; Q is 1-P (progress 0 to 1)
    linear)
        io='st(1, Q)'
        i="$io"
        o="$io"
        ;;
    quadratic)
        i='st(1, Q^2)'
        o='st(1, 1 - P^2)'
        io='st(1, if(gt(P, 0.5), 2 * Q^2, 1 - 2 * P^2))'
        ;;
    cubic)
        i='st(1, Q^3)'
        o='st(1, 1 - P^3)'
        io='st(1, if(gt(P, 0.5), 4 * Q^3, 1 - 4 * P^3))'
        ;;
    quartic)
        i='st(1, Q^4)'
        o='st(1, 1 - P^4)'
        io='st(1, if(gt(P, 0.5), 8 * Q^4, 1 - 8 * P^4))'
        ;;
    quintic)
        i='st(1, Q^5)'
        o='st(1, 1 - P^5)'
        io='st(1, if(gt(P, 0.5), 16 * Q^5, 1 - 16 * P^5))'
        ;;
    sinusoidal)
        i='st(1, 1 - sin(P * PI / 2))'
        o='st(1, cos(P * PI / 2))'
        io='st(1, (1 + cos(P * PI)) / 2)'
        ;;
    exponential)
        i='st(1, if(eq(P, 1), 0, 2^(-10 * P)))'
        o='st(1, if(eq(P, 0), 1, 1 - 2^(-10 * Q)))'
        io='st(1, if(gt(P, 0.5), if(eq(P, 1), 0, 2^(9 - 20 * P)), if(eq(P, 0), 1, 1 - 2^(20 * P - 11))))'
        ;;
    circular)
        i='st(1, 1 - sqrt(1 - Q^2))'
        o='st(1, sqrt(1 - P^2))'
        io='st(1, if(gt(P, 0.5), 1 - sqrt(1 - 4 * Q^2), 1 + sqrt(1 - 4 * P^2)) / 2)'
        ;;
    elastic)
        i='st(1, cos(20 * P * PI / 3) / 2^(10 * P))'
        o='st(1, 1 - cos(20 * Q * PI / 3) / 2^(10 * Q))'
        _make
        _make 'st(1, 2 * Q - 1);'
        _make 'st(2, cos(40 * ld(1) * PI / 9) / 2);'
        _make 'st(3, 2^(10 * ld(1)));'
        _make 'st(1, if(gt(P, 0.5), ld(2) * ld(3), 1 - ld(2) / ld(3)))'
        io=$made
        ;;
    back)
        i='st(1, Q^2 * (Q * K1 - K))'
        o='st(1, 1 - P^2 * (P * K1 - K))'
        io='st(1, if(gt(P, 0.5), 2 * Q^2 * (2 * Q * H1 - H), 1 - 2 * P^2 * (2 * P * H1 - H)))'
        ;;
    bounce)
        _make
        _make ' st(2, 121 / 16);'
        _make ' if(lt(P, 4 / 11),'
        _make '  ld(2) * P^2,'
        _make '  if(lt(P, 8 / 11),'
        _make '   ld(2) * (P - 6 / 11)^2 + 3 / 4,'
        _make '   if(lt(P, 10 / 11),'
        _make '    ld(2) * (P - 9 / 11)^2 + 15 / 16,'
        _make '    ld(2) * (P - 21 / 22)^2 + 63 / 64'
        _make '   )'
        _make '  )'
        _make ' )'
        x=$made
        _make
        _make "st(1, $x);"
        _make 'st(1, 1 - ld(1))'
        i=$made
        x="${x//P/Q}"
        o="st(1, $x)"
        _make
        _make 'st(1, sgn(P - 0.5));'
        _make 'st(0, ld(1) * (2 * P - 1));'
        _make "st(2, $x);"
        _make 'st(1, (1 - ld(1) * ld(2)) / 2)'
        io=$made
        ;;
    esac
    x="$io"
    [[ $2 == in ]] && x="$i"
    [[ $2 == out ]] && x="$o"
    x="${x//H1/$H1}"
    x="${x//H/$H}"
    x="${x//K1/$K1}"
    x="${x//K/$K}"
    echo "$x"
}

# custom expressions for supplementary easings
_se_easing() { # easing mode
    local i o io # mode expressions
    local x # expr
    case $1 in
    squareroot) # opposite to quadratic (not Pohoreski's sqrt)
        i='st(1, sqrt(Q))'
        o='st(1, 1 - sqrt(P))'
        io='st(1, if(gt(P, 0.5), sqrt(2 * Q), 2 - sqrt(2 * P)) / 2)'
    ;;
    cuberoot) # opposite to cubic
        i='st(1, pow(Q, 1 / 3))'
        o='st(1, 1 - pow(P, 1 / 3))'
        io='st(1, if(gt(P, 0.5), pow(2 * Q, 1 / 3), 2 - pow(2 * P, 1 / 3)) / 2)'
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
    x="${x//Q/$P}"
    x="st(0, 1 - P);%n$x;%nst(0, 1 - ld(1))" # xfade progress goes from 1 to 0
    echo "$x" # f(P) in ld(0)
    exit 0
}

# custom expressions for Xfade transitions
# see https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_xfade.c
_xf_transition() { # transition
    local x # expr
    local s r
    _make
    case $1 in
    fade)
        _make 'mix(A, B, P)'
        ;;
    fadefast|fadeslow)
        r=1 && s=+
        [[ $1 =~ slow ]] && r=2 && s=-
        _make 'st(1, 1 / max);' # imax
        _make "st(1, pow(P, 1 + log($r $s abs(A - B) * ld(1))));"
        _make 'mix(A, B, ld(1))'
        ;;
    fadeblack|fadewhite)
        s=black
        [[ $1 =~ white ]] && s=white
        _make "st(1, $s);" # bg
        _make 'st(2, smoothstep(0.8, 1, P, 2));'
        _make 'st(2, mix(A, ld(1), ld(2)));'
        _make 'st(3, smoothstep(0.2, 1, P, 3));'
        _make 'st(3, mix(ld(1), B, ld(3)));'
        _make 'mix(ld(2), ld(3), P)'
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
        _make 'st(1, (2 * abs(P - 0.5))^3 * hypot(W / 2, H / 2));' # z
        _make 'st(2, hypot(X - W / 2, Y - H / 2));' # dist
        _make 'st(3, if(lt(P, 0.5), B, A));' # val
        _make 'if(lt(ld(1), ld(2)), black, ld(3))'
        ;;
    rectcrop)
        _make 'st(1, abs(P - 0.5) * W);' # zw
        _make 'st(2, abs(P - 0.5) * H);' # zh
        _make 'st(3, lt(abs(X - W / 2), ld(1) * lt(abs(Y - H / 2), ld(2))));' # dist
        _make 'st(4, if(lt(P, 0.5), B, A));' # val
        _make 'if(not(ld(3)), black, ld(4))'
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
    dissolve)
        _make 'st(1, frand(X, Y, 1));'
        _make 'st(1, ld(1) * 2 + P * 2 - 1.5);' # smooth
        _make 'if(gte(ld(1), 0.5), A, B)'
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
        _make 'st(1, if(lte(ld(2), ld(1)), 0, 1));' # ss
        _make 'mix(B, A, ld(1))'
        ;;
    radial)
        _make 'st(1, atan2(X - W / 2, Y - H / 2) - (P - 0.5) * PI * 2.5);' # smooth
        _make 'st(1, smoothstep(0, 1, ld(1), 1));'
        _make 'mix(B, A, ld(1))'
        ;;
    squeezeh)
        _make 'st(1, 0.5 + (Y / H - 0.5) / P);' # z
        _make 'if(between(ld(1), 0, 1),'
        _make ' st(2, round(ld(1) * (H - 1)));'
        _make ' a(X, ld(2)),'
        _make ' B'
        _make ')'
        ;;
    squeezev)
        _make 'st(1, 0.5 + (X / W - 0.5) / P);' # z
        _make 'if(between(ld(1), 0, 1),'
        _make ' st(2, round(ld(1) * (W - 1)));'
        _make ' a(ld(2), Y),'
        _make ' B'
        _make ')'
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
#   distance) needs 2 passes of PLANE
#   hblur) needs 2 passes of X, Y
#   fadegrays) needs 2 passes of PLANE
    esac
    x=$made
    echo "$x"
}

# custom expressions for GLTransitions
# # see https://github.com/gl-transitions/gl-transitions/tree/master/transitions
_gl_transition() { # transition args
    local x # expr
    local a=(${2//,/ }) # args
    local s
    _make
    case $1 in
    gl_angular)
        _make "st(1, ${a[0]-90});" # startingAngle
        _make 'st(2, 1 - P);'
        _make 'st(1, ld(1) * PI / 180);' # offset
        _make 'st(1, atan2(0.5 - Y / H, X / W - 0.5) + ld(1));' # angle
        _make 'st(1, (ld(1) + PI) / (2 * PI));' # normalizedAngle
        _make 'st(1, ld(1) - floor(ld(1)));'
        _make 'st(1, step(ld(1), ld(2)));'
        _make 'mix(A, B, ld(1))'
        ;;
    gl_CrazyParametricFun)
        _make "st(1, ${a[0]-4});" # a
        _make "st(2, ${a[1]-1});" # b
        _make "st(3, ${a[2]-120});" # amplitude
        _make "st(4, ${a[3]-0.1});" # smoothness
        _make 'st(5, 1 - P);'
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
    gl_crosswarp)
        _make 'st(1, 1 - P);' # x
        _make 'st(1, ld(1) * 2 + X / W - 1);'
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
    gl_directionalwarp)
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
    gl_kaleidoscope)
        _make "st(1, ${a[0]-1});" # speed
        _make "st(2, ${a[1]-1});" # angle
        _make "st(3, ${a[2]-1.5});" # power
        _make 'st(4, 1 - P);'
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
    gl_multiply_blend)
        _make 'st(1, A * B / max);'
        _make 'st(2, 2 * (1 - P));'
        _make 'if(gt(P, 0.5), mix(A, ld(1), ld(2)), st(2, ld(2) - 1); mix(ld(1), B, ld(2)))'
        ;;
    gl_pinwheel)
        _make "st(1, ${a[0]-2});" # speed
        _make 'st(1, atan2(0.5 - Y / H, X / W - 0.5) + (1 - P) * ld(1));' # circPos
        _make 'st(1, mod(ld(1), PI / 4));' # modPos
        _make 'st(1, sgn(1 - P - ld(1)));' # signed
        _make 'st(1, step(ld(1), 0.5));'
        _make 'mix(B, A, ld(1))'
        ;;
    gl_polar_function)
        _make "st(1, ${a[0]-5});" # segments
        _make 'st(2, X / W - 0.5);'
        _make 'st(3, 0.5 - Y / H);'
        _make 'st(4, atan2(ld(3), ld(2)) - PI / 2);' # angle
        _make 'st(4, cos(ld(1) * ld(4)) / 4 + 1);' # radius
        _make 'st(1, hypot(ld(2), ld(3)));' # difference
        _make 'if(gt(ld(1), ld(4) * (1 - P)), A, B)'
        ;;
    gl_PolkaDotsCurtain)
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
    gl_randomsquares)
        _make "st(1, ${a[0]-10});" # size.x
        _make "st(2, ${a[1]-10});" # size.y
        _make "st(3, ${a[2]-0.5});" # smoothness
        _make 'st(1, floor(ld(1) * X / W));'
        _make 'st(2, floor(ld(2) * (1 - Y / H)));'
        _make 'st(4, sin(dot(ld(1), ld(2), 12.9898, 78.233)));'
        _make 'st(4, fract(ld(4) * 43758.5453));' # r
        _make 'st(4, ld(4) - ((1 - P) * (1 + ld(3))));'
        _make 'st(4, smoothstep(0, -ld(3), ld(4), 4));' # m
        _make 'mix(A, B, ld(4))'
        ;;
    gl_ripple)
        _make "st(1, ${a[0]-100});" # amplitude
        _make "st(2, ${a[1]-50});" # speed
        _make 'st(3, X / W - 0.5);' # dir.x
        _make 'st(4, 0.5 - Y / H);' # dir.y
        _make 'st(5, hypot(ld(3), ld(4)));' # dist
        _make 'st(6, 1 - P);'
        _make 'st(5, (sin(ld(6) * (ld(5) * ld(1) - ld(2))) + 0.5) / 30);'
        _make 'st(3, ld(3) * ld(5));' # offset.x
        _make 'st(4, ld(4) * ld(5));' # offset.y
        _make 'st(3, (X / W + ld(3)) * W);'
        _make 'st(4, (1 - ((1 - Y / H) + ld(4))) * H);'
        _make 'st(1, a(ld(3), ld(4)));'
        _make 'st(2, smoothstep(0.2, 1, ld(6), 2));'
        _make 'mix(ld(1), B, ld(2))'
        ;;
    gl_rotate_scale_fade)
        _make "st(1, ${a[0]-0.5});" # centre.x
        _make "st(2, ${a[1]-0.5});" # centre.y
        _make "st(3, ${a[2]-1});" # rotations
        _make "st(4, ${a[3]-8});" # scale
        s=black; [[ ${a[4]-0} != 0 ]] && s=white # backColor(0=black;!0=white)
        _make 'st(5, 1 - P);'
        _make 'st(6, X / W - ld(1));' # difference.x
        _make 'st(7, (1 - Y / H) - ld(2));' # difference.y
        _make 'st(8, hypot(ld(6), ld(7)));' # dist
        _make 'st(6, ld(6) / ld(8));' # dir.x
        _make 'st(7, ld(7) / ld(8));' # dir.y
        _make 'st(3, 2 * PI * ld(3) * ld(5));' # angle
        _make 'st(9, 2 * abs(P - 0.5));'
        _make 'st(4, mix(ld(4), 1, ld(9)));' # currentScale
        _make 'st(6, st(9, ld(6)) * cos(ld(3)) - ld(7) * sin(ld(3)));' # rotatedDir.x
        _make 'st(7, ld(9) * sin(ld(3)) + ld(7) * cos(ld(3)));' # rotatedDir.y
        _make 'st(1, ld(1) + ld(6) * ld(8) / ld(4));' # rotatedUv.x
        _make 'st(2, ld(2) + ld(7) * ld(8) / ld(4));' # rotatedUv.y
        _make 'if(between(ld(1), 0, 1) * between(ld(2), 0, 1),'
        _make ' st(1, ld(1) * W);'
        _make ' st(2, (1 - ld(2)) * H);'
        _make ' st(1, a(ld(1), ld(2)));'
        _make ' st(2, b(ld(1), ld(2)));'
        _make ' mix(ld(1), ld(2), ld(5)),'
        _make " $s"
        _make ')'
        ;;
    gl_squareswire)
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
        _make 'st(5, lt(P, 1) * step(ld(5), ld(1)) * step(ld(5), ld(2)) * step(ld(1), ld(6)) * step(ld(2), ld(6)));' # a
        _make 'mix(A, B, ld(5))'
        ;;
    gl_Swirl)
        _make 'st(1, 1);' # Radius
        _make 'st(2, 1 - P);' # T
        _make 'st(3, X / W - 0.5);' # UV.x
        _make 'st(4, 0.5 - Y / H);' # UV.y
        _make 'st(5, hypot(ld(3), ld(4)));' # Dist
        _make 'if(lt(ld(5), ld(1)),'
        _make ' st(1, (ld(1) - ld(5)) / ld(1));' # Percent
        _make ' st(5, ld(2) * 2);'
        _make ' st(5, if(lte(ld(2), 0.5), mix(0, 1, ld(5)), st(5, ld(5) - 1); mix(1, 0, ld(5))));' # A
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
    gl_WaterDrop)
        _make "st(1, ${a[0]-30});" # amplitude
        _make "st(2, ${a[1]-30});" # speed
        _make 'st(3, X / W - 0.5);' # dir.x
        _make 'st(4, 0.5 - Y / H);' # dir.y
        _make 'st(5, hypot(ld(3), ld(4)));' # dist
        _make 'st(6, A);'
        _make 'if(lte(ld(5), 1 - P),'
        _make ' st(1, sin(ld(5) * ld(1) - (1 - P) * ld(2)));'
        _make ' st(3, ld(3) * ld(1));' # offset.x
        _make ' st(4, ld(4) * ld(1));' # offset.y
        _make ' st(3, X + ld(3) * W);'
        _make ' st(4, Y - ld(4) * H);'
        _make ' st(6, a(ld(3), ld(4)))'
        _make ');'
        _make 'mix(B, ld(6), P)'
        ;;
    esac
    x=$made
    echo "$x"
}

# custom expressions for supplementary transitions
_st_transition() { # transition
    local x # expr
    _make
    case $1 in
    x_screen_blend) # modelled on gl_multiply_blend
        _make 'st(1, (1 - (1 - A / max) * (1 - B / max)) * max);'
        _make 'st(2, 2 * (1 - P));'
        _make 'if(gt(P, 0.5),'
        _make ' mix(A, ld(1), ld(2)),'
        _make ' st(2, ld(2) - 1); mix(ld(1), B, ld(2))'
        _make ')'
        ;;
    x_overlay_blend) # modelled on gl_multiply_blend
        _make 'st(1, if(lte(A, mid), 2 * A * B / max, (1 - 2 * (1 - A / max) * (1 - B / max)) * max));'
        _make 'st(2, 2 * (1 - P));'
        _make 'if(gt(P, 0.5),'
        _make ' mix(A, ld(1), ld(2)),'
        _make ' st(2, ld(2) - 1); mix(ld(1), B, ld(2))'
        _make ')'
        ;;
#   x_step) # no transition, steps at halfway point
#       x='if(gt(P, 0.5), A, B)'
#       ;;
    esac
    x=$made
    echo "$x"
}

# get transition expression
_transition() { # transition
    local x=$(_xf_transition $1) # try Xfade
    [[ -n $x ]] && is_xf=true
    [[ -z $x ]] && x=$(_gl_transition $1 $2) # try GL
    [[ -z $x ]] && x=$(_st_transition $1) # try supplementary
    [[ -z $x ]] && exit $ERROR # unknown transition name
    local s r
    for s in rem mix fract smoothstep frand a b dot step; do # expand pseudo functions
        while [[ $x =~ $s\( ]]; do
            r=$(_heredoc FUNC | gawk -v e="$x" -v f=$s -f-)
            x=${r%%|*} # search
            r=${r#*|} # args
            [[ $s == mix && -n $is_xf ]] && r+=' xf' # xfade mix args are different
            r=$(_$s $r) # replace
            x=${x/@/$r} # expand
        done
    done
    for s in black white max mid; do # expand pseudo variables
        r=p_$s # replace
        x=${x//$s/${!r}} # expand
    done
    echo "$x"
    exit 0
}

# set pixel format
_format() { # pix_fmt
    ffmpeg -hide_banner -pix_fmts > $TMP-pixfmts.txt
    local depth=$(_heredoc PIXFMT | gawk -v format=$1 -f- $TMP-pixfmts.txt)
    [[ -z $depth ]] && _error "unknown format: $1" && return $ERROR
    local is_rgb=0
    [[ $1 =~ (rgb|bgr|gbr|rbg|bggr|rggb) ]] && is_rgb=1 # (from libavutil/pixdesc.c)
    p_max=$(((1<<$depth)-1))
    p_mid=$(($p_max/2))
    if [[ $is_rgb -ne 0 ]]; then
        p_black="if(lt(PLANE,3), 0, $p_max)"
        p_white=$p_max
    else
        p_black="if(eq(PLANE,0), 0, if(lt(PLANE,3), $p_mid, $p_max))"
        p_white="if(eq(PLANE,0)+eq(PLANE,3), $p_max, $p_mid)"
    fi
    return 0
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
    local ll=24 # log level warning
    local expr mode
    for mode in in out inout; do
        expr=$(_easing $2 $mode)
        expr="$expr; if(eq(PLANE,0)*eq(X,0)*eq(Y,0), print(-1,$ll); print(1-P,$ll); print(1-$P,$ll))"
        expr=$(_expand '%x' "$expr")
        local log=$TMP-plot-$mode.log
        export FFREPORT="file=$log:level=$ll" # prints to log file
        ffmpeg $FFOPTS -loglevel +repeat+error -filter_complex_threads 1 \
            -f lavfi -i "color=c=black:s=1x1:r=100:d=3,format=gray" \
            -f lavfi -i "color=c=white:s=1x1:r=100:d=3,format=gray" \
            -filter_complex "[0][1]xfade=duration=1:offset=1:transition=custom:expr='$expr'" -f null -
    done
    unset FFREPORT # prevent further logging
    local size=$(_size ${o_psize-$PLOTSIZE} $PLOTSIZE)
    local plt=$TMP-plot.plt # gnuplot script
    _heredoc PLOT | gawk -v title=$2 -v size=$size -v h=${PLOTSIZE#*x} -v output="$path" -f- $TMP-plot-*.log > $plt
    gnuplot $plt
}

# output demo video
_video() { # path
    local path=$(_expand "$1") file enc
    local inputs=(${2//,/ })
    local n=${#inputs[@]} i j
    if [[ $n -lt 2 ]]; then
        n=2
        inputs=(sheep goat)
        for i in 0 1; do
            file=$TMP-${inputs[i]}.png
            _heredoc ${inputs[i]^^} | base64 -D -o $file
            inputs[$i]=$file
        done
    fi
    local m=$((n-1))
    local length=${o_vlength-$VIDEOLENGTH}
    local duration=${o_vtduration-$VIDEOTRANSITIONDURATION}
    local offset=$(_calc "($length - $duration) / 2")
    local expr=$(_expand '%n%X')
    local fps=${o_vfps-$VIDEOFPS}
    [[ $path =~ .gif && $fps -gt 50 ]] && fps=50 # max for browser support
    local dims=$(_dims ${inputs[0]})
    local size=$(_size ${o_vsize-$dims} $dims 1) # even
    local width=${size%x*}
    local height=${size#*x}
    local fsmult=${o_vfsmult-$VIDEOFSMULT}
    local bb=$(_calc "int(3 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled boxborder
    local fs=$(_calc "int(16 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled fontsize
    local drawtext="drawtext=x='(w-text_w)/2':y='(h-text_h)/2':box=1:boxborderw=$bb:text_align=C:fontsize=$fs:text='TEXT'"
    local text1=$transition text2=$transition
    [[ -n $args ]] && text1+=$(_expand '=%A') && text2+=$(_expand '=%a')
    [[ $easing != linear ]] && text1+=$(_expand '%nno easing') && text2+=$(_expand '%n%e-%m')
    readarray -d , -n 3 -t a <<<$VIDEOSTACK,
    local stack=${a[0]} gap=${a[1]} fill=${a[2]}
    readarray -d , -n 3 -t a <<<$o_vstack,,,
    [[ -n ${a[0]} ]] && stack=${a[0]} ; [[ -n ${a[1]} ]] && gap=${a[1]} ; [[ -n ${a[2]} ]] && fill=${a[2]}
    local script=$TMP-script.txt # filter_complex_script
    rm -f $script
    for i in $(seq 0 1 $m); do
        local loop=$(_calc "int(($length + $duration) / 2 * $fps) + 1")
        [[ $i -gt 0 && $i -lt $m ]] && loop=$(_calc "$loop * 2")
        cat << EOT >> $script
movie='${inputs[i]}',
format=pix_fmts=$format,
scale=width=$width:height=$height,
loop=loop=$loop:size=1,
fps=fps=$fps
[v$i];
EOT
    done
    # alt: testsrc=size=$size:rate=$fps:duration=$d:decimals=3
    #      testsrc2=size=$size:rate=$fps:duration=$d
    if [[ -z $stack || ( $easing == linear && -z $args ) ]]; then # unstacked
        if [[ -n $o_vname ]]; then
            for i in $(seq 0 1 $m); do
                echo "[v$i]${drawtext/TEXT/$text2}[v$i];" >> $script
            done
        fi
        echo "[v0]null[v];" >> $script
        for j in $(seq $m); do
            i=$((j-1))
            echo "[v][v$j]xfade=offset=$offset:duration=$duration:transition=custom:expr='$expr'[v];" >> $script
            offset=$(_calc "$offset + $length")
        done
    else # stacked
        [[ -z $stack || $stack == a ]] && stack=v && [[ $transition =~ (up|down|vu|vd|squeezeh|horz) ]] && stack=h
        local cell2="$gap+w0_0"
        [[ $stack == v ]] && cell2="0_h0+$gap"
        local trans=$transition # xfade transition
        if [[ $transition =~ _ ]]; then # custom transition
            expr=$(_expand "%n%Z")
            [[ -n $args ]] && expr=$(_transition $transition) && expr=$(_expand "%n%X" "$expr") # default args
            trans="custom:expr='$expr'"
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
            echo "[va][v${j}a]xfade=offset=$offset:duration=$duration:transition=$trans[va];" >> $script
            echo "[vb][v${j}b]xfade=offset=$offset:duration=$duration:transition=custom:expr='$expr'[vb];" >> $script
            offset=$(_calc "$offset + $length")
        done
        echo "[va][vb]xstack=inputs=2:fill=$fill:layout=0_0|$cell2[v];" >> $script
    fi
    if [[ $path =~ .gif ]]; then # animated for .md
        echo '[v]split[s0][s1]; [s0]palettegen[s0]; [s1][s0]paletteuse=dither=none[v]' >> $script
    elif [[ $path =~ .mkv ]]; then # lossless - see https://trac.ffmpeg.org/wiki/Encode/FFV1
        enc="-c:v ffv1 -level 3 -coder 1 -context 1 -g 1 -pix_fmt yuv420p -r $fps"
    else # x264 - see https://trac.ffmpeg.org/wiki/Encode/H.264
        enc="-c:v libx264 -pix_fmt yuv420p -r $fps"
    fi
    length=$(_calc "$length * $m")
    ffmpeg $FFOPTS -filter_complex_threads 1 -filter_complex_script $script -map [v]:v -an -t $length $enc "$path"
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
/^[^-0-9]/ { next } # non-data
/^-1\.0+$/ { # start of data pair
    if (FILENAME != fn) { # new file
        fn = FILENAME
        match(fn, /-([inout]+)\.log$/, a)
        mode = a[1]
    }
    col = "p" # progress
    next
}
{
    if (col == "p")
        p = int($1 * 100 + 0.5) # (always integral anyway)
    else
        val[mode,p] = +$1
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
        print p, val["in",p], val["out",p], val["inout",p]
    print "EOD"
    print ""
    print "plot $data using 'progress':'in' with lines linestyle 1 title 'in', \\"
    print "     $data using 'progress':'out' with lines linestyle 2 title 'out', \\"
    print "     $data using 'progress':'inout' with lines linestyle 3 title 'inout'"
}
!PLOT

@LIST # list transitions & easings filtered from this script for -L option
BEGIN {
    title["rp"] = "Easing Functions (Robert Penner):"
    title["se"] = "Supplementary Easings:"
    title["xf"] = "Xfade Transitions:"
    title["gl"] = "GL Transitions:"
    title["st"] = "Supplementary Transitions:"
}

$1 ~ /^#/ { next }

match($1, /^_(..)_(transition|easing)\(\)/, a) { # transition/easing func
    go = 1
    if (cases)
        print ""
    print title[a[1]]
}

match($1, /^([A-Za-z_|]+)\)$/, a) && go { # case
    cases = a[1]
    args = defs = c = ""
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
        print a[i], args, defs
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
FFmpeg Xfade Easing script ($CMD version $VERSION) by Raymond Luckhurst, scriptit.uk
Generates custom xfade filter expressions for rendering transitions with easing.
See https://ffmpeg.org/ffmpeg-filters.html#xfade & https://trac.ffmpeg.org/wiki/Xfade
Usage: $CMD [options]
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
       %x expands to the generated expr, compact, best for inline filterchains
       %X does too but is more legible, good for filter_complex_script files
       %y expands to the easing expression only, compact; %Y legible
       %z expands to the eased transition expression only, compact; %Z legible
          for the uneased transition expression only, use -e linear (default) and %x or %X
       %n inserts a newline
    -p easing plot output filename (default: no plot)
       accepts expansions but %m/%M are pointless as plots show all easing modes
       formats: gif, jpg, png, svg, pdf, eps, html <canvas>, determined from file extension
    -c canvas size for easing plot (default: $PLOTSIZE, scaled to inches for PDF/EPS)
       format: WxH; omitting W or H keeps aspect ratio, e.g -z x300 scales W
    -v video output filename (default: no video), accepts expansions
       formats: animated gif, mp4 (x264 yuv420p), mkv (FFV1 lossless) from file extension
    -i video inputs CSV (2 or more needed, default: sheep,goat - inline pngs $VIDEOSIZE)
    -z video size (default: input 1 size)
       format: WxH; omitting W or H keeps aspect ratio, e.g -z 300x scales H
    -l video length per transition (default: ${VIDEOLENGTH}s)
       total length is this length times (number of inputs - 1)
    -d video transition duration (default: ${VIDEOTRANSITIONDURATION}s)
    -r video framerate (default: ${VIDEOFPS}fps)
    -n show effect name on video as text
    -u video text font size multiplier (default: $VIDEOFSMULT)
    -2 video stack orientation,gap,colour (default: $VIDEOSTACK), e.g. h,2,red
       stacks uneased and eased videos horizontally (h), vertically (v) or auto (a)
       auto (a) selects the orientation that displays easing to best effect
       also stacks transitions with default and custom parameters, eased or not
       videos are not stacked unless they are different (nonlinear or customised)
    -L list all transitions and easings
    -H show this usage text
    -V show the script version
    -T temporary file directory (default: $TMPDIR)
    -K keep temporary files if temporary directory is not $TMPDIR
Notes:
    1. point the shebang path to a bash4 location (defaults to MacPorts install)
    2. this script requires Bash 4 (2009), gawk, gsed, envsubst, ffmpeg, gnuplot, base64
    3. use -filter_complex_threads 1 ffmpeg option (slower!) because xfade expressions
       are not thread-safe (the st() & ld() functions use contextual allocation)
    4. certain xfade transitions are not implemented because they perform aggregation
       (distance, fadegrays, hblur)
    5. a few GL Transitions are also ported, some of which take parameters;
       to override the default parameters append as CSV after an = sign,
       e.g. -t gl_PolkaDotsCurtain=10,0.5,0.5 for 10 dots centred
       (see https://gl-transitions.com/gallery)
    6. many transitions do not lend themselves well to easing, and easings that overshoot
       (back & elastic) may cause weird effects!
!USAGE
