#!/bin/bash
# lib/yaml_parser.sh - YAML parsing utility

parse_yaml() {
    local yaml_file=$1
    local prefix=${2:-"config_"}
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs="$(echo @|tr @ '\034')"

    # Resolve relative paths
    if [[ ! "$yaml_file" = /* ]]; then
        yaml_file="$ROOT_DIR/$yaml_file"
    fi

    if [ ! -f "$yaml_file" ]; then
        echo "Error: YAML file not found: $yaml_file" >&2
        return 1
    fi
    
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$yaml_file" |
    awk -F"$fs" '{
        indent = length($1)/2;
        if (length($2) == 0) { conj[indent]="+";} else {
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
            if (length($3) > 0) {
                # Clean the value by removing comments
                val = $3
                sub(/#.*$/, "", val)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                if (val != "") {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s=\"%s\"\n", "'"$prefix"'",vn, $2, val);
                }
            }
        }
    }'
}

get_enabled_modules() {
    local config_file=$1
    
    # Get only direct children of the modules section that have enabled: true
    parse_yaml "$config_file" | awk '
        BEGIN { FS="=" }
        /^config_modules_[^_]+_enabled="true"/ {
            # Extract module name between modules_ and _enabled
            match($1, /^config_modules_([^_]+)_enabled$/, arr)
            if (arr[1] != "" && arr[1] != "_order" && arr[1] != "_paths") {
                # Clean the module name
                module = arr[1]
                # Remove any comments and trim whitespace
                sub(/#.*$/, "", module)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", module)
                if (module != "") {
                    print module
                }
            }
        }
    '
}

get_module_config() {
    local config_file=$1
    local module_name=$2
    local prefix=${3:-"config_"}
    
    # Clean the module name
    module_name=$(echo "$module_name" | sed 's/#.*$//' | tr -d '[:space:]')
    
    parse_yaml "$config_file" | grep "^${prefix}modules_${module_name}_"
}

# If script is run directly, show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Usage: source $(basename $0)"
    echo "This script provides YAML parsing functions and should be sourced, not executed directly."
    exit 1
fi