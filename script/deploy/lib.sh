#!/bin/bash

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

load_env_file() {
    local file="$1"
    local line
    local key
    local value

    if [ ! -f "$file" ]; then
        echo -e "\033[31mError:\033[0m file not found: $file"
        return 1
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(trim_whitespace "$line")

        case "$line" in
            ''|\#*)
                continue
                ;;
            export\ *)
                line="${line#export }"
                line=$(trim_whitespace "$line")
                ;;
        esac

        case "$line" in
            *=*)
                key="${line%%=*}"
                value="${line#*=}"
                key=$(trim_whitespace "$key")
                value=$(trim_whitespace "$value")

                if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    echo -e "\033[31mError:\033[0m invalid key '$key' in $file"
                    return 1
                fi

                case "$value" in
                    \"*\")
                        value="${value#\"}"
                        value="${value%\"}"
                        ;;
                    \'*\')
                        value="${value#\'}"
                        value="${value%\'}"
                        ;;
                esac

                printf -v "$key" '%s' "$value"
                export "$key"
                ;;
            *)
                echo -e "\033[31mError:\033[0m invalid line in $file: $line"
                return 1
                ;;
        esac
    done < "$file"
}
