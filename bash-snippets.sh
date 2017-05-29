#!/bin/bash

##
# Usage for all functions in this library which return something:
#     function_name [-v var] function_opts_and_agrs ...
# If '-v var' present result will be assigned to the variable name 'var'
# instead of printing to stdout (as in bash printf function).
# 'var' must not have the same name as function local variables!
##


##
# Exit with optional message to stderr
##
quit() {
    [[ $2 ]] && echo "$2" >&2
    exit "$1"
}


##
# Sort positional arguments using iterative quicksort
# Note: preferred for small number of elements ~<10
# TODO: verify
##
qsort_i() {
    (($#==0)) && return 0
    local _var _res _stack _beg _end _i _pivot _smaller _larger
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    _stack=( 0 $(($#-1)) )
    _res=("$@")
    while ((${#_stack[@]})); do
        _beg=${_stack[0]}
        _end=${_stack[1]}
        _stack=("${_stack[@]:2}")
        _smaller=()
        _larger=()
        _pivot=${_res[_beg]}
        for ((_i=_beg+1;_i<=_end;++_i)); do
            if [[ "${_res[_i]}" < "${_pivot}" ]]; then
                _smaller+=("${_res[_i]}")
            else
                _larger+=("${_res[_i]}")
            fi
        done
        _res=("${_res[@]:0:_beg}" "${_smaller[@]}" "${_pivot}" "${_larger[@]}" "${_res[@]:_end+1}")
        ((${#_smaller[@]}>=2)) && _stack+=("${_beg}" "$((_beg+${#_smaller[@]}-1))")
        ((${#_larger[@]}>=2)) && _stack+=("$((_end-${#_larger[@]}+1))" "${_end}")
    done

    if [[ ${_var} ]]; then eval "${_var}=\${_res[@]}"; else echo "${_res[@]}"; fi
}


##
# Sorts positional arguments using recursive quicksort
# Note: preferred for large number of elements ~>10
# TODO: verify
##
qsort_r() {
    (($#==0)) && return 0
    local _var _res _i _pivot _smaller _larger
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    _smaller=()
    _larger=()
    _res=()
    _pivot=$1
    shift
    for _i; do
        if [[ ${_i} < ${_pivot} ]]; then
            _smaller+=( "${_i}" )
        else
            _larger+=( "${_i}" )
        fi
    done
    qsort_r "${_smaller[@]}"
    _smaller=("${_res[@]}")
    qsort_r "${larger[@]}"
    _larger=("${_res[@]}")
    _res=("${_smaller[@]}" "${_pivot}" "${_larger[@]}")

    if [[ ${_var} ]]; then eval "${_var}=(\${_res[@]})"; else echo "${_res[@]}"; fi
}


##
# Bash native simple alternative to curl/wget
# Set BWGET_* variables
# Support only few HTTP/1.1 features! No https, no compression, etc.
# Chunks join on 'Transfer-Encoding: chunked' is implemented but not properly tested.
# Args:
#   http url
#   optionaly HTTP GET options...
# Globals:
#   BWGET_HEADER
#   BWGET_BODY
# TODO: adopt to [-v var] usage
##
bwget() {
    unset BWGET_HEADER BWGET_BODY
    local LC_ALL RAW_RESPONSE BR HTTP_VERSION HTTP_URL HTTP_HOST HTTP_PORT HTTP_GET HTTP_GET_MORE_OPTS bwget_body_tmp o chunk_sz body_shift rval
    # local TIMEOUT
    LC_ALL=C
    BR=$'\r'$'\n'  # End of line required for GET request
    HTTP_VERSION='HTTP/1.1'
    HTTP_PORT=80
    HTTP_URL=${1#http://}  # Remove http:// prefix if any
    HTTP_HOST=${HTTP_URL%%[/?]*}  # Only domain or ip part
    HTTP_GET=${HTTP_URL#${HTTP_HOST}}  # GET request part (with leading / or ? or None)
    [[ -z ${HTTP_GET} || ${HTTP_GET::1} = '?' ]] && HTTP_GET=/${HTTP_GET}  # In case if HTTP_URL is domain name only or GET options has no leading /
    if [[ -z $2 ]]; then
        ## Defaults
        # HTTP_GET_MORE_OPTS+="User-Agent: bash${BR}"
        HTTP_GET_MORE_OPTS+="Accept: text/plain, text/*;q=0.9, */*;q=0.1${BR}"
        HTTP_GET_MORE_OPTS+="Accept-Encoding: identity, *;q=0${BR}"
    else
        ## Default HTTP_GET_MORE_OPTS will be overwritten
        shift
        for o in "$@"; do
            HTTP_GET_MORE_OPTS+="${o}${BR}"
        done
    fi
    # if [[ -n ${BWGET_TIMEOUT} ]]; then
    #     TIMEOUT=${BWGET_TIMEOUT}
    # else
    #     TIMEOUT=10  # Default
    # fi

    if exec 8<>"/dev/tcp/${HTTP_HOST}/${HTTP_PORT}"; then
        echo -n "GET ${HTTP_GET} ${HTTP_VERSION}${BR}Host: ${HTTP_HOST}${BR}${HTTP_GET_MORE_OPTS}Connection: close${BR}${BR}" >&8  # Send GET request
        # read -u 8 -d '' -t ${TIMEOUT} RAW_RESPONSE
        read -u 8 -d '' RAW_RESPONSE
        exec 8>&-  # Close file descriptor
    else
        return 1
    fi

    ## Separate header from body (should be separated by \r\n\r\n)
    BWGET_HEADER=${RAW_RESPONSE%%${BR}${BR}*}
    BWGET_BODY=${RAW_RESPONSE#${BWGET_HEADER}${BR}${BR}}

    ## Join chunks if any
    while read -r o; do
        o=${o%$'\r'}
        if [[ "${o}" = 'Transfer-Encoding: chunked' ]]; then
            body_shift=0  # Start of new chunk
            chunk_sz=1  # Just to enter to loop
            while true; do
                # tmp=${BWGET_BODY: ${body_shift}}  # DEV
                read chunk_sz <<<"${BWGET_BODY: ${body_shift}}" || { rval=128; break 2; }
                chunk_sz=${chunk_sz%$'\r'}  # Remove trailing \r, size in hex should be here now
                [[ "${chunk_sz}" = '0' ]] && break  # End of chunks
                ## Validation of chunk_sz, if invalid BWGET_BODY will not be overwrited.
                [[ "${chunk_sz}" =~ ^[0-9a-fA-F]+$ ]] || { rval=129; break 2; }
                ## Append current chunk body
                bwget_body_tmp+=${BWGET_BODY: $((body_shift+${#chunk_sz}+2)): $((16#${chunk_sz}))}
                (( body_shift += ${#chunk_sz}+4 + 16#${chunk_sz}))  # Update shift
            done
            BWGET_BODY=${bwget_body_tmp}
            break
        fi
    done <<<"${BWGET_HEADER}"

    ## Echo result
    # echo -n "${RAW_RESPONSE}"
    # echo -n "${BWGET_BODY}"

    return ${rval:=0}
}


##
# Convert decimal number to IPv4 address
##
dec2ip() {
    local _var _res _e _dot _octet _dec
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    _dec=$1
    for _e in {3..0}; do
        (( _octet = _dec/256**_e ))
        (( _dec -= _octet*256**_e ))
        _res+=${_dot}${_octet}
        _dot=.
    done

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Convert IPv4 address to decimal number
##
ip2dec() {
    local _var _res _a _b _c _d
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    IFS=. read -r _a _b _c _d <<<"$1"
    (( _res = _a*256**3 + _b*256**2 + _c*256 + _d ))

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Convert IPv4 MASK to CIDR
# Assumes that MASK have no gaps.
##
mask2cidr() {
    local _var _res _x
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    _x=${1##*255.}
    set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1}-${#_x})*2 )) "${_x%%.*}"
    _x=${1%%$3*}
    (( _res = $2 + ${#_x}/4 ))

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Convert CIDR to IPv4 MASK
##
cidr2mask() {
    local _var _res
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi
    [[ -z $1 ]] && set 0

    set -- $(( 5-($1/8) )) 255 255 255 255 $(( (255<<(8 - ($1%8)))&255 )) 0 0 0
    if (($1 > 1)); then shift "$1"; else shift; fi
    _res=${1:-0}.${2:-0}.${3:-0}.${4:-0}

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Return next subnet with the same size
# Subnet format is IPv4/CIDR
##
next_subnet() {
    local _var _res _ip _cidr _size _ip_dec _ip_next
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    _ip=${1%/*}
    _cidr=${1#*/}
    (( _size = 2**(32-_cidr) ))  # all IPs count inside subnet e.g. /29 size is 8
    ip2dec -v _ip_dec "${_ip}"
    dec2ip -v _ip_next $((_size+_ip_dec))
    _res=${_ip_next}/${_cidr}

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Return next IPv4 address
##
next_ip() {
    local _var _res _ip
    if [[ $1 == '-v' ]]; then _var=$2; shift 2; fi

    ip2dec -v _ip "$1"
    dec2ip -v _ip $((_ip+1))
    _res=${_ip}

    if [[ ${_var} ]]; then eval "${_var}=\${_res}"; else echo "${_res}"; fi
}


##
# Validate IPv4 address
# Note: this is invalid address: 192.168.000.001
##
validate_ip4() {
    local _re
    _re='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'
    [[ "$1" =~ ${_re} ]] && return 0 || return 1
}


##
# Validate IPv4/CIDR
##
validate_ip4cidr() {
    local _re
    _re='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\/([0-9]|[1-2][0-9]|3[0-2])$'
    [[ "$1" =~ ${_re} ]] && return 0 || return 1
}
