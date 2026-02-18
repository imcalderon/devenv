# JSON Conventions

- Use `get_module_config "module_name" ".jq.path" "default"` to read module config
- Use `get_json_value "$CONFIG_FILE" ".jq.path" "default"` to read global config
- Module configs live at `modules/<name>/config.json`
- Workflow definitions live at `workflows/<type>/workflow.json`
- Validate with `jq empty <file>` before committing JSON changes
- Schemas in `schemas/` — validate with `check-jsonschema` or `ajv`
