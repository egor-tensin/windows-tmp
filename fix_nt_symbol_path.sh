#!/usr/bin/env bash

# Copyright (c) 2016 Egor Tensin <Egor.Tensin@gmail.com>
# This file is part of the "Windows tmp directory" project.
# For details, see https://github.com/egor-tensin/windows-tmp.
# Distributed under the MIT License.

# "Fixes" the value of _NT_SYMBOL_PATH environment variable by
#
# * including the path to the "pdbs" directory in this repository,
# * adding the "symbols" directory as a local "symbol store", mirroring
# Microsoft's http://msdl.microsoft.com/download/symbols.

# usage: ./fix_nt_symbol_path.sh [-h|--help] [-y|--yes] [-d|--dir TMP_DIR]

set -o errexit
set -o nounset
set -o pipefail

script_argv0="${BASH_SOURCE[0]}"
script_dir="$( cd "$( dirname "$script_argv0" )" && pwd )"

dump() {
    local prefix="${FUNCNAME[0]}"

    if [ "${#FUNCNAME[@]}" -gt 1 ]; then
        prefix="${FUNCNAME[1]}"
    fi

    while [ "$#" -ne 0 ]; do
        echo "$prefix: $1" || true
        shift
    done
}

str_tolower() {
    while [ "$#" -ne 0 ]; do
        echo "$1" | tr '[:upper:]' '[:lower:]'
        shift
    done
}

str_contains() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} STR SUB" || true
        return 1
    fi

    local str="$1"
    local sub
    sub="$( printf '%q' "$2" )"

    test "$str" != "${str#*$sub}"
}

readonly path_separator=';'

path_contains() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR" || true
        return 1
    fi

    local env_value
    env_value="$( str_tolower "$1" )"
    local path_to_add
    path_to_add="$( str_tolower "$2" )"

    local -a env_paths
    local env_path

    IFS="$path_separator" read -ra env_paths <<< "$env_value"

    for env_path in ${env_paths[@]+"${env_paths[@]}"}; do
        if [ "$env_path" == "$path_to_add" ]; then
            return 0
        fi
    done

    return 1
}

path_append() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR" || true
        return 1
    fi

    local env_value="$1"
    local path_to_add="$2"

    if ! path_contains "$env_value" "$path_to_add"; then
        if [ -z "$env_value" ]; then
            echo "$path_to_add"
        else
            echo "$path_separator$path_to_add"
        fi
    fi
}

prompt_to_continue() {
    local prefix="${FUNCNAME[0]}"
    if [ "${#FUNCNAME[@]}" -gt 1 ]; then
        prefix="${FUNCNAME[1]}"
    fi

    local prompt_reply
    while true; do
        echo -n "$prefix: continue? (y/n) "
        IFS= read -r prompt_reply
        prompt_reply="$( str_tolower "$prompt_reply" )"
        case "$prompt_reply" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     continue ;;
        esac
    done
}

ensure_reg_available() {
    if command -v reg.exe > /dev/null; then
        return 0
    else
        dump "reg.exe could not be found" >&2
        return 1
    fi
}

registry_set_string() {
    if [ "$#" -ne 3 ]; then
        echo "usage: ${FUNCNAME[0]} KEY_PATH VALUE_NAME VALUE_DATA" || true
        return 1
    fi

    ensure_reg_available

    local key_path="$1"
    local value_name="$2"
    local value_data="$3"

    reg.exe add "$key_path" /v "$value_name" /t REG_SZ /d "$value_data" /f > /dev/null
}

tmp_dir=

update_tmp_dir() {
    if [ "$#" -ne 1 ]; then
        echo "usage: ${FUNCNAME[0]} DIR" || true
        return 1
    fi

    tmp_dir="$( cygpath --windows --absolute "$1" )"
}

update_tmp_dir "$script_dir"

readonly key_path='HKCU\Environment'
readonly var_name='_NT_SYMBOL_PATH'

parse_script_options() {
    while [ "$#" -ne 0 ]; do
        local key="$1"
        shift

        case "$key" in
            -h|--help)
                exit_with_usage=0
                break
                ;;

            -y|--yes)
                skip_prompt=1
                continue
                ;;

            -d|--tmp-dir)
                ;;

            *)
                dump "usage error: unrecognized parameter: $key" >&2
                exit_with_usage=1
                break
                ;;
        esac

        if [ "$#" -eq 0 ]; then
            dump "usage error: missing argument for parameter: $key" >&2
            exit_with_usage=1
            break
        fi

        local value="$1"
        shift

        case "$key" in
            -d|--tmp-dir)
                update_tmp_dir "$value"
                ;;

            *)
                dump "usage error: unrecognized parameter: $key" >&2
                exit_with_usage=1
                break
                ;;
        esac
    done
}

exit_with_usage() {
    echo "usage: $script_argv0 [-h|--help] [-y|--yes] [-d|--tmp-dir DIR]" || true
    exit "${exit_with_usage:-0}"
}

fix_nt_symbol_path() {
    parse_script_options "$@"
    [ -n "${exit_with_usage+x}" ] && exit_with_usage

    dump "temporary directory path: $tmp_dir"

    if [ -z "${skip_prompt+x}" ]; then
        prompt_to_continue || return 0
    fi

    local pdbs_dir="$tmp_dir\\pdbs"
    local symbols_dir="$tmp_dir\\symbols"
    local srv_str="SRV*$symbols_dir*http://msdl.microsoft.com/download/symbols"
    local vscache_dir="$tmp_dir\\vscache"

    dump "directories:"
    dump "    custom PDB files: $pdbs_dir"
    dump "    symbol store: $symbols_dir"
    dump "    Visual Studio project cache files: $vscache_dir"

    local old_value="${!var_name-}"
    dump "old $var_name value: $old_value"
    local new_value="$old_value"

    new_value+="$( path_append "$new_value" "$pdbs_dir" )"
    new_value+="$( path_append "$new_value" "$srv_str" )"

    [ "$new_value" == "$old_value" ] && return 0
    dump "new $var_name value: $new_value"

    if [ -z "${skip_prompt+x}" ]; then
        prompt_to_continue || return 0
    fi

    registry_set_string "$key_path" "$var_name" "$new_value"
}

fix_nt_symbol_path "$@"
