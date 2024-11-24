#!/bin/bash
# lib/yaml_parser.sh - YAML parsing utility

parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$yaml_file" |
    awk -F"$fs" '{
        indent = length($1)/2;
        if (length($2) == 0) { conj[indent]="+";} else {
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
            if (length($3) > 0) {
                vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                printf("%s%s%s=\"%s\"\n", "'"$prefix"'",vn, $2, $3);
            }
        }
    }'
}

get_enabled_modules() {
    local config=$(parse_yaml "$CONFIG_FILE")
    echo "$config" | grep "enabled=\"true\"" | cut -d'_' -f2 | cut -d'=' -f1
}