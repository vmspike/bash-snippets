#!/bin/bash

## qsort's based on http://stackoverflow.com/a/30576368/4629599

##
# Sorts positional arguments using iterative quicksort
# Globals:
#   QSORTED
# Returns:
#   QSORTED (array)
# Note:
#   Iterative (preferred for small number of elements ~<10)
##
iqsort() {
    (($#==0)) && return 0
    local stack beg end i pivot smaller larger
    stack=( 0 $(($#-1)) )
    QSORTED=("$@")
    while ((${#stack[@]})); do
        beg=${stack[0]}
        end=${stack[1]}
        stack=("${stack[@]:2}")
        smaller=()
        larger=()
        pivot=${QSORTED[beg]}
        for ((i=beg+1;i<=end;++i)); do
            if [[ "${QSORTED[i]}" < "${pivot}" ]]; then
                smaller+=("${QSORTED[i]}")
            else
                larger+=("${QSORTED[i]}")
            fi
        done
        QSORTED=("${QSORTED[@]:0:beg}" "${smaller[@]}" "$pivot" "${larger[@]}" "${QSORTED[@]:end+1}")
        if ((${#smaller[@]}>=2)); then stack+=("$beg" "$((beg+${#smaller[@]}-1))"); fi
        if ((${#larger[@]}>=2)); then stack+=("$((end-${#larger[@]}+1))" "$end"); fi
    done
}


##
# Sorts positional arguments using recursive quicksort
# Globals:
#   QSORTED
# Returns:
#   QSORTED (array)
# Note:
#   Recursive (preferred for large number of elements ~>10)
##
rqsort() {
    (($#==0)) && return 0
    local pivot i smaller larger
    smaller=()
    larger=()
    QSORTED=()
    pivot=$1
    shift
    for i; do
        if [[ $i < $pivot ]]; then
            smaller+=( "$i" )
        else
            larger+=( "$i" )
        fi
    done
    qsort "${smaller[@]}"
    smaller=("${QSORTED[@]}")
    qsort "${larger[@]}"
    larger=("${QSORTED[@]}")
    QSORTED=("${smaller[@]}" "$pivot" "${larger[@]}")
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
