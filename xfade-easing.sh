#!/opt/local/bin/bash
set -o posix

# FFmpeg XFade easing expressions by Raymond Luckhurst, Scriptit UK, https://scriptit.uk
# GitHub: owner scriptituk; repository xfade-easing; https://github.com/scriptituk/xfade-easing
#
# This is a port of Robert Penner's easing equations for the FFmpeg expression evaluator
# It also ports most xfade transitions and some GL Transitions for use with easing
#
# See https://github.com/scriptituk/xfade-easing for documentation or use the -H option
# See https://ffmpeg.org/ffmpeg-utils.html#Expression-Evaluation for FFmpeg expressions

export CMD=`basename $0`
export VERSION=1.11
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
export VIDEOSIZE=250x200 # sheep/goad png (5:4)
export VIDEOLENGTH=5
export VIDEOTRANSITIONDURATION=3
export VIDEOFPS=25
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
    [[ -n $o_vstack ]] && vstack=$o_vstack

    [[ -n $o_list ]] && _list && exit 0
    [[ -n $o_help ]] && _help && exit 0
    [[ -n $o_version ]] && _version && exit 0

    _format $format || exit $ERROR # set pix format vars

    [[ ! $mode =~ ^(in|out|inout)$ ]] && _error "unknown easing mode '$mode'" && exit $ERROR

    easing_expr=$(_easing $easing $mode) # get easing expr
    [[ -z $easing_expr ]] && _error "unknown easing '$easing'" && exit $ERROR

    transition_expr=$(_transition $transition $args) # get transition expr
    [[ -z $transition_expr ]] && _error "unknown transition '$transition'" && exit $ERROR

    if [[ $easing == linear ]]; then
        expr="$transition_expr" # no easing needed
    else
        expr=$(gsed -e "s/\<P\>/$P/g" <<<$transition_expr) # eased progress in ld(0)
        expr="$easing_expr%n;%n$expr" # chained easing & transition
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
    for s in gawk gsed envsubst gnuplot ffmpeg base64; do
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

# vf_xfade.c mix(a,b,mix)
# (not subexpression safe: group first)
# for non-xfade transitions swap a & b because P goes 0..1
_mix() { # a b mix
    echo "$1 * $3 + $2 * (1 - $3)"
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
    [[ $2 == 0 ]] && d="- $1"
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

# dot product
_dot() { # x1 y1 x2 y2
    echo "$1 * $3 + $2 * $4"
}

# OpenGL step(edge,x)
_step() { # edge x
    echo "if(lt($2, $1), 0, 1)"
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

# custom expressions for XFade transitions
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
    _make
    case $1 in
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
        _make 'mix(ld(7), ld(6), ld(1))'
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
        _make 'mix(ld(7), ld(6), ld(1))'
        ;;
    gl_multiply_blend)
        _make 'st(1, A * B / max);'
        _make 'st(2, 2 * (1 - P));'
        _make 'if(gt(P, 0.5), mix(ld(1), A, ld(2)), st(2, ld(2) - 1); mix(B, ld(1), ld(2)))'
        ;;
    gl_pinwheel)
        _make "st(1, ${a[0]-2});" # speed
        _make 'st(1, atan2(0.5 - Y / H, X / W - 0.5) + (1 - P) * ld(1));' # circPos
        _make 'st(1, mod(ld(1), PI / 4));' # modPos
        _make 'st(1, sgn(1 - P - ld(1)));' # signed
        _make 'st(1, step(ld(1), 0.5));'
        _make 'mix(A, B, ld(1))'
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
        _make 'mix(B, ld(1), ld(2))'
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
        _make ' st(5, if(lte(ld(2), 0.5), mix(1, 0, ld(5)), st(5, ld(5) - 1); mix(0, 1, ld(5))));' # A
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
        _make 'mix(ld(6), ld(5), ld(2))'
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
        _make 'mix(ld(6), B, P)'
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
        _make ' mix(ld(1), A, ld(2)),'
        _make ' st(2, ld(2) - 1); mix(B, ld(1), ld(2))'
        _make ')'
        ;;
    x_overlay_blend) # modelled on gl_multiply_blend
        _make 'st(1, if(lte(A, mid), 2 * A * B / max, (1 - 2 * (1 - A / max) * (1 - B / max)) * max));'
        _make 'st(2, 2 * (1 - P));'
        _make 'if(gt(P, 0.5),'
        _make ' mix(ld(1), A, ld(2)),'
        _make ' st(2, ld(2) - 1); mix(B, ld(1), ld(2))'
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
    local x=$(_xf_transition $1) # try XFade
    [[ -z $x ]] && x=$(_gl_transition $1 $2) # try GL
    [[ -z $x ]] && x=$(_st_transition $1) # try supplementary
    [[ -z $x ]] && exit $ERROR # unknown transition name
    local s r
    for s in rem mix fract smoothstep frand a b dot step; do # expand pseudo functions
        while [[ $x =~ $s\( ]]; do
            r=$(_heredoc FUNC | gawk -v e="$x" -v f=$s -f-)
            x=${r%%|*} # search
            r=${r#*|} # args
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
    local inputs=(- ${2/,/ })
    if [[ -z $2 ]]; then
        inputs=(- sheep goat)
        for i in 1 2; do
            file=$TMP-${inputs[i]}.png
            _heredoc ${inputs[i]^^} | base64 -D -o $file
            inputs[$i]=$file
        done
    fi
    local length=${o_vlength-$VIDEOLENGTH}
    local duration=${o_vtduration-$VIDEOTRANSITIONDURATION}
    local offset=$(_calc "($length - $duration) / 2")
    local expr=$(_expand '%n%X')
    local xfade="offset=$offset:duration=$duration:transition=custom:expr='$expr'"
    local fps=${o_vfps-$VIDEOFPS}
    local fsmult=${o_vfsmult-$VIDEOFSMULT}
    [[ $path =~ .gif && $fps -gt 50 ]] && fps=50 # max for browser support
    local loop=$(_calc "int(($length + $duration) / 2 * $fps) + 1")
    local dims=$(_dims ${inputs[1]})
    local size=$(_size ${o_vsize-$dims} $dims 1) # even
    local width=${size%x*}
    local height=${size#*x}
    local b=$(_calc "int(3 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled border
    local fs=$(_calc "int(16 / ${VIDEOSIZE#*x} * $height * $fsmult + 0.5)" ) # scaled font
    local drawtext="drawtext=x='(w-text_w)/2':y='(h-text_h)/2':box=1:boxborderw=$b:text_align=C:fontsize=$fs:text='TEXT'"
    local text1=$transition text2=$transition
    [[ -n $args ]] && text1+=$(_expand '=%A') && text2+=$(_expand '=%a')
    [[ $easing != linear ]] && text1+=$(_expand '%nno easing') && text2+=$(_expand '%n%e-%m')
    local borders=(- SaddleBrown Orange)
    [[ -n $2 ]] && b=0 # no fillborders
    local script=$TMP-script.txt # filter_complex_script
    rm -f $script
    for i in 1 2; do
        cat << EOT >> $script
movie='${inputs[i]}',
format=pix_fmts=$format,
scale=width=$width:height=$height,
loop=loop=$loop:size=1,
fps=fps=$fps,
fillborders=$b:$b:$b:$b:mode=fixed:color=${borders[i]}
[v$i];
EOT
    done
    # alt: testsrc=size=$size:rate=$fps:duration=$d:decimals=3
    #      testsrc2=size=$size:rate=$fps:duration=$d
    if [[ -z $vstack || ( $easing == linear && -z $args ) ]]; then # unstacked
        if [[ -n $o_vname ]]; then
            cat << EOT >> $script
[v1]${drawtext/TEXT/$text2}[v1];
[v2]${drawtext/TEXT/$text2}[v2];
EOT
        fi
        cat << EOT >> $script
[v1][v2]
xfade=$xfade
[v];
EOT
    else # stacked
        local stack=v
        [[ $transition =~ (up|down|vu|vd|squeezeh|horz) ]] && stack=h
        [[ $vstack != a ]] && stack=$vstack
        local trans=$transition # xfade transition
        if [[ $transition =~ _ ]]; then # custom transition
            expr=$(_expand "%n%Z")
            [[ -n $args ]] && expr=$(_transition $transition) && expr=$(_expand "%n%X" "$expr") # default args
            trans="custom:expr='$expr'"
        fi
        cat << EOT >> $script
[v1]split[v1a][v1b];
[v2]split[v2a][v2b];
EOT
        if [[ -n $o_vname ]]; then
            cat << EOT >> $script
[v1a]${drawtext/TEXT/$text1}[v1a];
[v2a]${drawtext/TEXT/$text1}[v2a];
[v1b]${drawtext/TEXT/$text2}[v1b];
[v2b]${drawtext/TEXT/$text2}[v2b];
EOT
        fi
        cat << EOT >> $script
[v1a][v2a]
xfade=offset=$offset:duration=$duration:transition=$trans
[va];
[v1b][v2b]
xfade=$xfade
[vb];
[va][vb]${stack}stack[v];
EOT
    fi
    if [[ $path =~ .gif ]]; then # animated for .md
        echo '[v]split[s0][s1]; [s0]palettegen[s0]; [s1][s0]paletteuse[v]' >> $script
    elif [[ $path =~ .mkv ]]; then # lossless - see https://trac.ffmpeg.org/wiki/Encode/FFV1
        enc="-c:v ffv1 -level 3 -coder 1 -context 1 -g 1 -pix_fmt yuv420p -r $fps"
    else # x264 - see https://trac.ffmpeg.org/wiki/Encode/H.264
        enc="-c:v libx264 -pix_fmt yuv420p -r $fps"
    fi
    ffmpeg $FFOPTS -filter_complex_threads 1 -filter_complex_script $script -map [v]:v -an -t $length $enc "$path"
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
    title["xf"] = "XFade Transitions:"
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
lFTkSuQmCC
!SHEEP

@GOAT # goat PNG
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
!GOAT

@USAGE # CLI usage for -H option
FFmpeg XFade Easing script ($CMD version $VERSION) by Raymond Luckhurst, scriptit.uk
Generates custom xfade filter expressions for rendering transitions with easing.
See https://ffmpeg.org/ffmpeg-filters.html#xfade & https://trac.ffmpeg.org/wiki/Xfade
Usage: $CMD [options]
Options:
    -f pixel format (default: $FORMAT): use ffmpeg -pix_fmts for list
    -t transition name (default: $TRANSITION): use -L for list
    -e easing function (default: $EASING; standard Robert Penner easing functions):
       see -L for list
    -m easing mode (default: $MODE): in out inout
    -x expr output filename (default: no expr), accepts expansions
    -a append to expr output file
    -s expr output format string (default: $EXPRFORMAT)
       %t expands to the transition name; %e easing name; %m easing mode
       %T, %E, %M upper case expansions of above
       %a expands to the transition arguments; %A to the default arguments (if any)
       %x expands to the generated expr, compact, best for inline filterchains
       %X does too but is more legible, good for filter_complex_script files
       %y expands to the easing expression, compact; %Y legible
       %z expands to the transition expression, compact; %Z legible
       %n inserts a newline
    -p easing plot output filename (default: no plot)
       accepts expansions but %m/%M is pointless as plots show all easing modes
       formats: gif, jpg, png, svg, pdf, eps, html <canvas>, determined from file extension
    -c canvas size for easing plot (default: $PLOTSIZE, scaled to inches for EPS)
       format: WxH; omitting W or H scales to ratio 4:3, e.g -z x300 scales W
    -v video output filename (default: no video), accepts expansions
       formats: animated gif, mp4 (x264 yuv420p), mkv (FFV1 lossless) from file extension
    -i video inputs CSV (default: sheep,goat - inline pngs $VIDEOSIZE)
    -z video size (default: input 1 size)
       format: WxH; omitting W or H scales to ratio 5:4, e.g -z 300x scales H
    -l video length (default: $VIDEOLENGTH)
    -d video transition duration (default: $VIDEOTRANSITIONDURATION)
    -r video framerate (default: $VIDEOFPS)
    -n show effect name on video as text
    -u video text font size multiplier (default: $VIDEOFSMULT)
    -2 stack uneased and eased videos horizontally (h), vertically (v) or auto (a)
       auto selects the orientation that displays the easing to best effect
       stacking nly works for non-linear easings (default: no stack)
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
