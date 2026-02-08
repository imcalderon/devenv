#!/bin/bash
# lib/scaffold.sh - Project scaffolding engine
# Creates new projects from workflow-defined templates

# Tracked scaffold variables — only these get substituted in templates.
# This prevents accidental expansion of ${CMAKE_*} or other syntax.
declare -a _SCAFFOLD_VARS=()

# Register a variable for template substitution
_register_scaffold_var() {
    local key="$1"
    _SCAFFOLD_VARS+=("$key")
}

# Render a .tmpl file by substituting only registered scaffold variables.
# Non-registered ${VAR} patterns (like CMake variables) are left untouched.
render_template() {
    local template_file="$1"
    local output_file="$2"

    mkdir -p "$(dirname "$output_file")"

    # Build a sed expression that replaces only known variables
    local sed_args=()
    for varname in "${_SCAFFOLD_VARS[@]}"; do
        local value="${!varname:-}"
        # Escape sed special characters in the value
        value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
        sed_args+=(-e "s|\${${varname}}|${value}|g")
    done

    if [[ ${#sed_args[@]} -gt 0 ]]; then
        sed "${sed_args[@]}" "$template_file" > "$output_file"
    else
        cp "$template_file" "$output_file"
    fi
}

# Load variables from a workflow.json and register them for substitution.
# Reads both top-level .variables and subtype-specific .subtypes.<sub>.variables
load_workflow_variables() {
    local workflow_file="$1"
    local subtype="${2:-}"

    # Always load top-level variables
    local vars
    vars=$(jq -r '.variables // {} | to_entries[] | "\(.key)=\(.value)"' "$workflow_file" 2>/dev/null)
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        export "$key=$value"
        _register_scaffold_var "$key"
    done <<< "$vars"

    # Overlay subtype-specific variables if present
    if [[ -n "$subtype" ]]; then
        local st_vars
        st_vars=$(jq -r ".subtypes.\"$subtype\".variables // {} | to_entries[] | \"\(.key)=\(.value)\"" "$workflow_file" 2>/dev/null)
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            export "$key=$value"
            _register_scaffold_var "$key"
        done <<< "$st_vars"
    fi
}

# Resolve the scaffold directory for a workflow type
# Returns the path to the scaffold template directory
resolve_scaffold_dir() {
    local scaffolds_root="$1"
    local workflow_file="$2"
    local subtype="${3:-}"

    local scaffold_path=""

    if [[ -n "$subtype" ]]; then
        scaffold_path=$(jq -r ".subtypes.\"$subtype\".scaffold // empty" "$workflow_file" 2>/dev/null)
    fi

    if [[ -z "$scaffold_path" ]]; then
        scaffold_path=$(jq -r '.scaffold // empty' "$workflow_file" 2>/dev/null)
    fi

    if [[ -z "$scaffold_path" ]]; then
        return 1
    fi

    echo "$scaffolds_root/$scaffold_path"
}

# Copy and render all files from a scaffold directory into the target
# .tmpl files get rendered (variable substitution), others copied as-is
scaffold_directory() {
    local source_dir="$1"
    local target_dir="$2"

    if [[ ! -d "$source_dir" ]]; then
        return 0
    fi

    # Use find to traverse all files in the scaffold directory
    while IFS= read -r -d '' src_file; do
        local rel_path="${src_file#$source_dir/}"
        local dest_path="$target_dir/$rel_path"

        if [[ "$src_file" == *.tmpl ]]; then
            # Render template: strip .tmpl extension
            dest_path="${dest_path%.tmpl}"
            render_template "$src_file" "$dest_path"
        else
            # Copy as-is
            mkdir -p "$(dirname "$dest_path")"
            cp "$src_file" "$dest_path"
        fi
    done < <(find "$source_dir" -type f -print0)
}

# Main scaffolding function
# Creates a new project from workflow templates
scaffold_project() {
    local project_name="$1"
    local project_type="$2"
    local location="${3:-.}"

    local target_dir="$location/$project_name"
    local devenv_root="${DEVENV_ROOT:-$ROOT_DIR}"
    local scaffolds_root="$devenv_root/scaffolds"
    local workflows_root="$devenv_root/workflows"

    # Parse type:subtype
    local base_type="$project_type"
    local subtype=""
    if [[ "$project_type" == *:* ]]; then
        base_type="${project_type%%:*}"
        subtype="${project_type#*:}"
    fi

    # Validate workflow exists
    local workflow_file="$workflows_root/$base_type/workflow.json"
    if [[ ! -f "$workflow_file" ]]; then
        log "ERROR" "Unknown project type: $base_type"
        log "INFO" "Use --list-types to see available types"
        return 1
    fi

    # Validate subtype if provided
    if [[ -n "$subtype" ]]; then
        local valid_subtype
        valid_subtype=$(jq -r ".subtypes.\"$subtype\" // empty" "$workflow_file" 2>/dev/null)
        if [[ -z "$valid_subtype" ]]; then
            log "ERROR" "Unknown sub-type '$subtype' for workflow '$base_type'"
            local available
            available=$(jq -r '.subtypes | keys[]?' "$workflow_file" 2>/dev/null)
            if [[ -n "$available" ]]; then
                log "INFO" "Available sub-types: $available"
            fi
            return 1
        fi
    fi

    # Check target doesn't already exist
    if [[ -d "$target_dir" ]]; then
        log "ERROR" "Directory already exists: $target_dir"
        return 1
    fi

    log "INFO" "Creating $project_type project: $project_name"

    # Reset scaffold variable tracking
    _SCAFFOLD_VARS=()

    # Export standard variables
    export PROJECT_NAME="$project_name"
    _register_scaffold_var "PROJECT_NAME"
    export PROJECT_TYPE="$project_type"
    _register_scaffold_var "PROJECT_TYPE"

    # Load workflow variables into environment (also registers them)
    load_workflow_variables "$workflow_file" "$subtype"

    # Create target directory
    mkdir -p "$target_dir"

    # Copy common scaffold first
    if [[ -d "$scaffolds_root/common" ]]; then
        log "DEBUG" "Applying common scaffold..."
        scaffold_directory "$scaffolds_root/common" "$target_dir"
    fi

    # Copy type-specific scaffold
    local scaffold_dir
    scaffold_dir=$(resolve_scaffold_dir "$scaffolds_root" "$workflow_file" "$subtype")
    if [[ -n "$scaffold_dir" && -d "$scaffold_dir" ]]; then
        log "DEBUG" "Applying $project_type scaffold from $scaffold_dir..."
        scaffold_directory "$scaffold_dir" "$target_dir"
    else
        log "WARN" "No scaffold templates found for type: $project_type"
    fi

    # Initialize git repo
    if command -v git &>/dev/null; then
        log "DEBUG" "Initializing git repository..."
        git -C "$target_dir" init -q
        git -C "$target_dir" add -A
        git -C "$target_dir" commit -q -m "Initial scaffold: $project_type project"
    fi

    log "INFO" "Project created: $target_dir"
}

# List available project types
list_project_types() {
    local devenv_root="${DEVENV_ROOT:-$ROOT_DIR}"
    local workflows_root="$devenv_root/workflows"

    log "INFO" "Available project types:"
    for wf_dir in "$workflows_root"/*/; do
        local wf_name
        wf_name=$(basename "$wf_dir")
        local wf_file="$wf_dir/workflow.json"
        [[ -f "$wf_file" ]] || continue

        local desc
        desc=$(jq -r '.description // "No description"' "$wf_file")
        log "INFO" "  $wf_name - $desc"

        # Show subtypes
        local subtypes
        subtypes=$(jq -r '.subtypes | keys[]?' "$wf_file" 2>/dev/null)
        if [[ -n "$subtypes" ]]; then
            while IFS= read -r st; do
                local st_desc
                st_desc=$(jq -r ".subtypes.\"$st\".description // \"\"" "$wf_file")
                log "INFO" "    $wf_name:$st - $st_desc"
            done <<< "$subtypes"
        fi
    done
}
