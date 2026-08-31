.PHONY: help test lint check sandbox sandbox-zsh docker docker-all dry doctor install status clean

SHELL := /bin/bash

SCRIPTS := bin/kickstart install.sh shell/khelp.sh \
           test/smoke.sh test/sandbox.sh test/docker.sh
LIBS    := $(wildcard lib/*.sh) $(wildcard shell/*.sh)
SOURCES := $(wildcard shell/source/*.sh)
MODULES := $(wildcard modules/*/module.sh)

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk -F':.*?## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## --- safe to run against your real machine ----------------------------------

dry: ## Show what an apply would do here, change nothing
	@./bin/kickstart apply --dry-run

doctor: ## Check this machine's kickstart install
	@./bin/kickstart doctor

status: ## Show what this host is set up as
	@./bin/kickstart status

## --- isolated -----------------------------------------------------------------

test: ## Assertions against a throwaway $$HOME (no installs, no network)
	@./test/smoke.sh

sandbox: ## Interactive login shell in a throwaway $$HOME
	@./test/sandbox.sh --dirty

sandbox-zsh: ## Same, under zsh
	@./test/sandbox.sh --dirty --shell zsh

docker: ## Full bootstrap incl. package installs, in a disposable container
	@./test/docker.sh

docker-all: ## Same, across ubuntu / debian / fedora
	@./test/docker.sh --all

lint: ## shellcheck everything
	@command -v shellcheck >/dev/null || { \
	  echo "shellcheck not installed: brew install shellcheck"; exit 1; }
	@shellcheck -x $(SCRIPTS)
	@shellcheck -x --shell=bash $(LIBS) $(MODULES)
	@shellcheck -x --shell=sh $(SOURCES)
	@echo "lint ok"

check: lint test ## Lint and test -- run this before committing

## --- maintenance --------------------------------------------------------------

install: ## Apply this checkout to the current machine (for real)
	@./bin/kickstart apply

clean: ## Remove backup directories older than 30 days
	@find "$${XDG_STATE_HOME:-$$HOME/.local/state}/kickstart/backups" \
	  -maxdepth 1 -type d -mtime +30 -print -exec rm -rf {} + 2>/dev/null || true
