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

dump() {
    local prefix="${FUNCNAME[0]}"
    if [ "${#FUNCNAME[@]}" -gt 1 ]; then
        prefix="${FUNCNAME[1]}"
    fi
    while [ "$#" -ne 0 ]; do
        echo "$prefix: $1"
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
        echo "usage: ${FUNCNAME[0]} STR SUB"
        return 1
    fi
    local str="$1"
    local sub="$( printf '%q' "$2" )"
    test "$str" != "${str#*$sub}"
}

path_separator=';'

path_contains() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR_PATH"
        return 1
    fi
    local env_value="$( str_tolower "$1" )"
    local path_to_add="$( str_tolower "$2" )"
    local -a env_paths=()
    IFS="$path_separator" read -ra env_paths <<< "$env_value"
    local env_path
    for env_path in "${env_paths[@]+"${env_paths[@]}"}"; do
        if [ "$env_path" == "$path_to_add" ]; then
            return 0
        fi
    done
    return 1
}

path_append() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR_PATH"
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
        read -r prompt_reply
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

registry_set_string() (
    if [ "$#" -ne 3 ]; then
        echo "usage: ${FUNCNAME[0]} KEY_PATH VALUE_NAME VALUE_DATA"
        return 1
    fi

    set -o errexit

    ensure_reg_available

    local key_path="$1"
    local value_name="$2"
    local value_data="$3"

    reg.exe add "$key_path" /v "$value_name" /t REG_SZ /d "$value_data" /f > /dev/null
)

fix_nt_symbol_path() (
    set -o errexit

    local tmp_dir="$( cygpath -aw "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )"

    while [ "$#" -ne 0 ]; do
        local option="$1"
        shift

        case "$option" in
            -y|--yes)
                local skip_prompt=
                continue
                ;;

            -h|--help)
                local exit_with_usage=0
                break
                ;;
        esac

        if [ "$#" -eq 0 ]; then
            dump "usage error: missing argument for parameter: $option" >&2
            local exit_with_usage=1
            break
        fi

        case "$option" in
            -d|--dir)
                tmp_dir="$( cygpath -aw "$1" )"
                shift
                ;;

            *)
                dump "usage error: unknown parameter: $option" >&2
                local exit_with_usage=1
                break
                ;;
        esac
    done

    if [ -n "${exit_with_usage+x}" ]; then
        echo "usage: ${FUNCNAME[0]} [-h|--help] [-y|--yes] [-d|--dir TMP_DIR]"
        return "${exit_with_usage:-0}"
    fi

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

    local old_value="${_NT_SYMBOL_PATH-}"
    dump "old _NT_SYMBOL_PATH value: $old_value"
    local new_value="$old_value"

    new_value+="$( path_append "$new_value" "$pdbs_dir" )"
    new_value+="$( path_append "$new_value" "$srv_str" )"

    [ "$new_value" == "$old_value" ] && return 0
    dump "new _NT_SYMBOL_PATH value: $new_value"

    if [ -z "${skip_prompt+x}" ]; then
        prompt_to_continue || return 0
    fi

    registry_set_string 'HKCU\Environment' '_NT_SYMBOL_PATH' "$new_value"
)

fix_nt_symbol_path "$@"
