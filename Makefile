.PHONY: help test lint check fmt install apply status clean

SHELL := /bin/bash

SCRIPTS := bin/kickstart install.sh shell/khelp.sh test/smoke.sh
LIBS    := $(wildcard lib/*.sh) $(wildcard shell/*.sh)
SOURCES := $(wildcard shell/source/*.sh)
MODULES := $(wildcard modules/*/module.sh)

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

test: ## Run the smoke tests against a throwaway $$HOME
	@./test/smoke.sh

lint: ## shellcheck everything
	@command -v shellcheck >/dev/null || { \
	  echo "shellcheck not installed: brew install shellcheck"; exit 1; }
	@shellcheck -x $(SCRIPTS)
	@shellcheck -x --shell=bash $(LIBS) $(MODULES)
	@shellcheck -x --shell=sh $(SOURCES)
	@echo "lint ok"

check: lint test ## Lint and test

install: ## Apply this checkout to the current machine
	@./bin/kickstart apply

status: ## Show what this host is set up as
	@./bin/kickstart status

clean: ## Remove backup directories older than 30 days
	@find "$${XDG_STATE_HOME:-$$HOME/.local/state}/kickstart/backups" \
	  -maxdepth 1 -type d -mtime +30 -print -exec rm -rf {} + 2>/dev/null || true
