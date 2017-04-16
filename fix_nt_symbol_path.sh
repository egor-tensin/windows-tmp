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

# usage: ./fix_nt_symbol_path.sh [-h|--help] [-y|--yes] [-d|--tmp-dir DIR]

set -o errexit
set -o nounset
set -o pipefail

script_name="$( basename -- "${BASH_SOURCE[0]}" )"
readonly script_name
script_dir="$( dirname -- "${BASH_SOURCE[0]}" )"
script_dir="$( cd -- "$script_dir" && pwd )"
readonly script_dir

dump() {
    local prefix="${FUNCNAME[0]}"
    [ "${#FUNCNAME[@]}" -gt 1 ] && prefix="${FUNCNAME[1]}"

    local msg
    for msg; do
        echo "$prefix: $msg"
    done
}

str_tolower() {
    local s
    for s; do
        echo "${s,,}"
    done
}

readonly path_separator=';'

path_contains() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR" >&2
        return 1
    fi

    local env_value
    env_value="$( str_tolower "$1" )"
    local path_to_add
    path_to_add="$( str_tolower "$2" )"

    local -a env_paths
    local env_path

    # Thanks to this guy for this trick:
    # http://stackoverflow.com/a/24426608/514684
    IFS="$path_separator" read -a env_paths -d '' -r < <( printf -- "%s$path_separator\\0" "$env_value" )

    for env_path in ${env_paths[@]+"${env_paths[@]}"}; do
        if [ "$env_path" == "$path_to_add" ]; then
            return 0
        fi
    done

    return 1
}

path_append() {
    if [ "$#" -ne 2 ]; then
        echo "usage: ${FUNCNAME[0]} ENV_VALUE DIR" >&2
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
    [ "${#FUNCNAME[@]}" -gt 1 ] && prefix="${FUNCNAME[1]}"

    local prompt_reply
    while true; do
        IFS= read -p "$prefix: continue? (y/n) " -r prompt_reply
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
        dump "couldn't find reg.exe" >&2
        return 1
    fi
}

registry_set_string() {
    if [ "$#" -ne 3 ]; then
        echo "usage: ${FUNCNAME[0]} KEY_PATH VALUE_NAME VALUE_DATA" >&2
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
        echo "usage: ${FUNCNAME[0]} DIR" >&2
        return 1
    fi

    tmp_dir="$( cygpath --windows --absolute -- "$1" )"
}

update_tmp_dir "$script_dir"

readonly env_key_path='HKCU\Environment'
readonly env_var_name='_NT_SYMBOL_PATH'

script_usage() {
    local msg
    for msg; do
        echo "$script_name: $msg"
    done

    echo "usage: $script_name [-h|--help] [-y|--yes] [-d|--tmp-dir DIR]"
}

parse_script_options() {
    while [ "$#" -ne 0 ]; do
        local key="$1"
        shift

        case "$key" in
            -h|--help)
                script_usage
                exit 0
                ;;
            -y|--yes)
                skip_prompt=1
                continue
                ;;
            -d|--tmp-dir)
                ;;
            *)
                script_usage "unrecognized parameter: $key" >&2
                exit 1
                ;;
        esac

        if [ "$#" -eq 0 ]; then
            script_usage "missing argument for parameter: $key" >&2
            exit 1
        fi

        local value="$1"
        shift

        case "$key" in
            -d|--tmp-dir)
                update_tmp_dir "$value"
                ;;
            *)
                script_usage "unrecognized parameter: $key" >&2
                exit 1
                ;;
        esac
    done
}

fix_nt_symbol_path() {
    dump "temporary directory path: $tmp_dir"

    if [ -z "${skip_prompt+x}" ]; then
        prompt_to_continue || return 0
    fi

    local pdbs_dir="$tmp_dir\\pdbs"
    local symbols_dir="$tmp_dir\\symbols"
    local srv_str="SRV*$symbols_dir*http://msdl.microsoft.com/download/symbols"
    local vscache_dir="$tmp_dir\\vscache"

    dump 'directories:'
    dump "    custom PDB files: $pdbs_dir"
    dump "    symbol store: $symbols_dir"
    dump "    Visual Studio project cache files: $vscache_dir"

    local old_value="${!env_var_name-}"
    dump "old $env_var_name value: $old_value"
    local new_value="$old_value"

    new_value+="$( path_append "$new_value" "$pdbs_dir" )"
    new_value+="$( path_append "$new_value" "$srv_str" )"

    [ "$new_value" == "$old_value" ] && return 0
    dump "new $env_var_name value: $new_value"

    if [ -z "${skip_prompt+x}" ]; then
        prompt_to_continue || return 0
    fi

    registry_set_string "$env_key_path" "$env_var_name" "$new_value"
}

main() {
    parse_script_options "$@"
    fix_nt_symbol_path
}

main "$@"
