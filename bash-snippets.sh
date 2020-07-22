#!/bin/bash

##
# Usage for most functions in this library which return something:
#   somefunc [-v VAR] agrs...
# If `-v foo` present the result will be assigned to the variable named "foo"
# (if the variable is unset global variable will be declared), othervise will
# be printed to stdout.
##


##
# Exit with optional message to stderr
# Example:
#   quit 1 Some error occured
##
quit() {
    if [[ -n "${*:2}" ]]; then
        if (($1==0)); then
            printf '%s\n' "${*:2}"
        else
            printf '%s\n' "${*:2}" >&2
        fi
    fi
    exit "${1:-0}"
}


##
# Sort positional arguments using quicksort.
# Automaticaly choose sort type (iterative or recursive) depends on array length.
#
# First argument have to be an option(s) with optional leading hyphen:
#   v: Put result to the variable specified in second argument.
#   e: Print resulting array with newline separated values.
#      Will be incorrect if array values contain newline characters.
#   n: Numeric sort instead of default lexical.
#   r: Reverse sort.
#
# Example:
#   # Sort numerical array ARR in reverse and put result to the array RES
#   qsort -vnr RES "${ARR[@]}"
##
qsort() {
    local opt var res i pivot smaller larger reverse=0
    local operator='<'  # Sort lexicographically using the current locale
    # local LC_ALL=C  # If want to sort irrelatively to locale
    opt=${1#-}  # Remove leading -
    for ((i=0; i<${#opt};i++)); do
        case "${opt:i:1}" in
            v)
                [[ -z $2 ]] && return 1
                var=$2; shift 2
                case "$#" in
                    0) eval "declare -g ${var}=()"; return $?;;
                    1) eval "declare -g ${var}=(\"\$1\")"; return $?;;
                esac
                ;;
            e)
                shift
                case "$#" in
                    0) return 0;;
                    1) printf %s "$1"; return 0;;
                esac
                ;;
            r) reverse=1;;
            n) operator='-lt';;  # Numeric sort
            *) echo "Invalid option: $1" >&2; return 1
        esac
    done
    if ((reverse)); then
        case "${operator}" in
            '<') operator='>';;
            '>') operator='<';;
            '-lt') operator='-gt';;
            '-gt') operator='-lt';;
        esac
    fi

    # Choose sort type based on array size
    if (($#<12)); then
        ## Iterative quicksort
        local stack beg end
        stack=( 0 $(($#-1)) )
        res=("$@")
        while ((${#stack[@]})); do
            beg=${stack[0]}
            end=${stack[1]}
            stack=("${stack[@]:2}")
            smaller=()
            larger=()
            pivot=${res[beg]}
            for ((i=beg+1;i<=end;i++)); do
                # The main comparison test
                if eval [[ "\${res[i]}" ${operator} "\${pivot}" ]]; then
                    smaller+=("${res[i]}")
                else
                    larger+=("${res[i]}")
                fi
            done
            res=("${res[@]:0:beg}" "${smaller[@]}" "${pivot}" "${larger[@]}" "${res[@]:end+1}")
            ((${#smaller[@]}>=2)) && stack+=("${beg}" "$((beg+${#smaller[@]}-1))")
            ((${#larger[@]}>=2)) && stack+=("$((end-${#larger[@]}+1))" "${end}")
        done
    else
        ## Recursive quicksort
        _qsort_r_feeg8Hoh() {
            if (($#==0)); then
                res=()
                return
            elif (($#==1)); then
                res=("$1")
                return
            elif (($#==2)); then
                if eval [[ "\$1" ${operator} "\$2" ]]; then
                    res=("$1" "$2")
                else
                    res=("$2" "$1")
                fi
                return
            fi

            local pivot smaller=() larger=() i
            pivot=$1; shift
            smaller=()
            larger=()
            for i in "$@"; do
                # The main comparison test
                if eval [[ "\${i}" ${operator} "\${pivot}" ]]; then
                    smaller+=("${i}")
                else
                    larger+=("${i}")
                fi
            done
            _qsort_r_feeg8Hoh "${smaller[@]}"
            smaller=("${res[@]}")
            _qsort_r_feeg8Hoh "${larger[@]}"
            larger=("${res[@]}")
            res=("${smaller[@]}" "${pivot}" "${larger[@]}")
        }
        _qsort_r_feeg8Hoh "$@"
        unset -f _qsort_r_feeg8Hoh
    fi

    if [[ -n ${var} ]]; then
        # shellcheck disable=2016
        eval "declare -g ${var}"='("${res[@]}")'
    else
        for i in "${res[@]}"; do
            printf '%s\n' "${i}"
        done
    fi
}


##
# Bash native simple alternative to curl/wget
# Set BWGET_* variables
# Supports only few HTTP/1.1 features! No https, no compression, etc.
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
# Converts decimal number to IPv4 address.
# Usage: dec2ip [-v VAR] IPv4ASANUMBER
##
dec2ip() {
    local _res _ip

    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -g "$2"
        local -n _res=$2
        shift 2
    else
        local _res
    fi

    _ip=$1
    _res=$((_ip%256))
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}

    [[ -R _res ]] || printf '%s\n' "${_res}"
}


##
# Converts IPv4 address to decimal number.
# Usage: ip2dec [-v VAR] IPv4
##
ip2dec() {
    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -g "$2"
        local -n _res=$2
        shift 2
    else
        local _res
    fi

    IFS=. read -ra _res <<<"$1"
    (( _res = _res[0]*16777216 + _res[1]*65536 + _res[2]*256 + _res[3] ))

    [[ -R _res ]] || printf '%s\n' "${_res}"
}


##
# Converts IPv4 MASK to CIDR.
# Assumes that MASK has no gaps.
# Usage: mask2cidr [-v VAR] MASK
##
mask2cidr() {
    local _x

    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -g "$2"
        local -n _res=$2
        shift 2
    else
        local _res
    fi

    _x=${1##*255.}
    set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1}-${#_x})*2 )) "${_x%%.*}"
    _x=${1%%$3*}
    (( _res = $2 + ${#_x}/4 ))

    [[ -R _res ]] || printf '%s\n' "${_res}"
}


##
# Converts CIDR to IPv4 MASK.
# Usage: cidr2mask [-v VAR] CIDR
##
cidr2mask() {
    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -g "$2"
        local -n _res=$2
        shift 2
    else
        local _res
    fi

    [[ -z $1 ]] && set 0

    set -- $(( 5-($1/8) )) 255 255 255 255 $(( (255<<(8 - ($1%8)))&255 )) 0 0 0
    if (($1 > 1)); then shift "$1"; else shift; fi
    _res=${1:-0}.${2:-0}.${3:-0}.${4:-0}

    [[ -R _res ]] || printf '%s\n' "${_res}"
}


##
# Returns next IPv4 subnet with the same size.
# Usage: next_subnet [-v VAR] IPv4[/CIDR]
# If CIDR is not specified defaults to 32 and the result will have no CIDR as well.
##
next_subnet() {
    local _ip _cidr

    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -ag "$2"
        local -n _res=$2
        shift 2
    else
        local -a _res
    fi

    IFS=/ read -r _ip _cidr <<<"$1"
    if [[ -z ${_cidr} ]]; then
        _cidr=('' 1)
    else
        _cidr=("${_cidr[0]}" "$((2**(32-_cidr[0])))")
    fi

    IFS=. read -ra _ip <<<"${_ip}"
    (( _ip = _ip[0]*16777216 + _ip[1]*65536 + _ip[2]*256 + _ip[3] ))

    _ip=$((_cidr[1]+_ip[0]))
    _res=$((_ip%256))
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}
    ((_ip>>=8))
    _res=$((_ip%256)).${_res}

    [[ -n ${_cidr[0]} ]] && _res+=/${_cidr[0]}

    [[ -R _res ]] || printf '%s\n' "${_res[0]}"
}


##
# Validates IPv4 address.
# Note: this is invalid address: 192.168.000.001
##
validate_ip4() {
    local _re
    _re='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'
    [[ "$1" =~ ${_re} ]] && return 0 || return 1
}


##
# Validates IPv4/CIDR.
##
validate_ip4cidr() {
    local _re
    _re='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\/([0-9]|[1-2][0-9]|3[0-2])$'
    [[ "$1" =~ ${_re} ]] && return 0 || return 1
}

##
# Generates pseudorandom string with desired length from specified source.
# Usage: bpwgen [-v VAR] LEN SRC
# Default LEN is 8.
# Default SRC is alphanumeric latin letters.
# If SRC starts with - and such option exists it has special meaning.
##
bpwgen() {
    local _src _sl _len _i

    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -g "$2"
        local -n _res=$2
        shift 2
    else
        local _res
    fi

    [[ -n "$1" ]] && _len=$1 || _len=8  # No check
    case "$2" in
        ''|-an|--alphanumeric)  # Default
            _src='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';;
        -a|--alpha)
            _src='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';;
        -n|--numeric)
            _src='0123456789';;
        -b|--no-ambiguous)
            _src='2345679abcdefghjkmnpqrstuvwxyzACEFGHJKLMNPRSTUVWXYZ';;
        -l|--lowercase)
            _src='0123456789abcdefghijklmnopqrstuvwxyz';;
        -u|--uppercase)
            _src='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';;
        -s|--secure)
            _src='!"#$%&()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'\';;
        *) _src=$2
    esac
    _sl=${#_src}
    for ((_i=0;_i<_len;_i++)); do
        _res+=${_src:$((RANDOM%_sl)):1}
    done

    [[ -R _res ]] || printf '%s\n' "${_res}"
}


##
# Returns array of network interface IP addresses.
# If no VAR specified, print space separated line.
# Depends on: ip (except -6 specified)
# Usage: get_ip [-v VAR] [-4|-6] IFACE
##
get_ip() {
    local _inet _iface _ip _x _i _seq

    if [[ "$1" == '-v' ]]; then
        [[ -v "$2" ]] || declare -ag "$2"
        local -n _res=$2
        shift 2
    else
        local -a _res
    fi

    case "$1" in
        -4|-6) _inet=$1; shift;;
        *) _inet=''
    esac
    _iface=$1

    if [[ "${_inet}" == '-6' && -r /proc/net/if_inet6 ]]; then
        # For ipv6-only use /proc/net/if_inet6 instead of parsing ip output
        _i=0
        while IFS=' ' read -r _ip _x _x _x _x _x; do
            if [[ "${_x}" == "${_iface}" ]]; then
                # Full colon separated representation
                _ip="${_ip:0:4}:${_ip:4:4}:${_ip:8:4}:${_ip:12:4}:${_ip:16:4}:${_ip:20:4}:${_ip:24:4}:${_ip:28:4}"

                # Compress the longest 0-nibble sequence
                _x=${_ip}  # Clone the value
                _seq=0000:0000:0000:0000:0000:0000:0000  # Start with 7 nibbles
                while [[ -n ${_seq} ]]; do
                    # Can lead to single leading or trailing : instead of :: if _seq is in the edge
                    _ip=${_ip/${_seq}}

                    if [[ "${_ip}" == "${_x}" ]]; then
                        # Not found, truncate one nibble
                        _seq=${_seq:5}
                        continue
                    fi

                    # Restore edge colon if missed
                    if [[ "${_ip::1}" == ':' ]]; then
                        _ip=":${_ip}"  # Restore leading colon
                    elif [[ "${_ip: -1}" == ':' ]]; then
                        _ip+=':'  # Restore trailing colon
                    fi
                    break  # The longest sequence compressed
                done

                # Remove leading zeroes in each nibble if any
                _ip=":${_ip}"
                _ip=${_ip//:00/:}
                _ip=${_ip//:0/:}
                _ip=${_ip:1}

                _res[$((_i++))]=${_ip}
            fi
        done </proc/net/if_inet6
    else
        # Parse ip output
        _i=0
        # shellcheck disable=2034
        while IFS=' /' read -r _x _x _x _ip _x; do
            _res[$((_i++))]=${_ip}
        done <<<"$(exec -c ip ${_inet} -o addr show "${_iface}")"
    fi

    [[ -R _res ]] || printf '%s\n' "${_res[*]}"
}
