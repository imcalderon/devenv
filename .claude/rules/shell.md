# Shell Script Conventions

- Always use `set -euo pipefail` in bash scripts
- Use `log "LEVEL" "message" "module"` for logging (levels: INFO, WARN, ERROR, DEBUG)
- Use `expand_vars` from lib/compat.sh for variable expansion — never `eval echo`
- Use `sed_inplace` from lib/compat.sh for portable sed — never raw `sed -i`
- Use `get_module_config` / `get_json_value` for JSON reading — never raw jq in modules
- Detect package managers at runtime: `command -v dnf`, `command -v apt-get`, `command -v brew`
- Use `conda run -n <env>` for commands in conda environments — never `conda activate`
- Module scripts must handle actions via case statement: install, remove, verify, info
