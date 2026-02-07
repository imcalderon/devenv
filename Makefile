.PHONY: lint lint-sh lint-json lint-ps test validate clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

lint: lint-sh lint-json ## Run all linters

lint-sh: ## Run ShellCheck on all bash scripts
	@echo "Running ShellCheck..."
	@find . -type f -name "*.sh" -not -path "./.git/*" -exec shellcheck {} +
	@echo "ShellCheck passed."

lint-json: ## Validate all JSON config files
	@echo "Validating JSON syntax..."
	@find . -type f -name "*.json" -not -path "./.git/*" -not -path "*/node_modules/*" \
		-exec sh -c 'for f do jq . "$$f" >/dev/null || exit 1; done' sh {} +
	@echo "JSON syntax validation passed."
	@echo "Validating JSON schemas..."
	@if command -v check-jsonschema >/dev/null 2>&1; then \
		check-jsonschema --schemafile schemas/config.schema.json config.json && \
		find modules -name "config.json" -exec check-jsonschema --schemafile schemas/module.schema.json {} + ; \
		echo "JSON schema validation passed."; \
	elif command -v ajv >/dev/null 2>&1; then \
		ajv validate -s schemas/config.schema.json -d config.json && \
		find modules -name "config.json" -exec ajv validate -s schemas/module.schema.json -d {} \; ; \
		echo "JSON schema validation passed."; \
	else \
		echo "Skipped: no JSON schema validator installed (pip install check-jsonschema or npm install -g ajv-cli)"; \
	fi

lint-ps: ## Run PSScriptAnalyzer on PowerShell scripts (requires pwsh)
	@echo "Running PSScriptAnalyzer..."
	@pwsh -Command "Get-ChildItem -Recurse -Filter '*.ps1' | ForEach-Object { \
		Invoke-ScriptAnalyzer -Path $$_.FullName -Severity Warning }" 2>/dev/null || \
		echo "Skipped: pwsh not available"

test: ## Run tests (requires bats-core)
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/; \
	else \
		echo "Skipped: bats-core not installed (npm install -g bats)"; \
	fi

validate: lint ## Alias for lint

clean: ## Remove generated files and caches
	@rm -rf tmp/ temp/ .cache/
	@find . -name "*.backup" -delete
	@echo "Cleaned."
