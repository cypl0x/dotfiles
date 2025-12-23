# Makefile for NixOS configuration management

# Variables
NIXOS_REBUILD ?= nixos-rebuild
NIX ?= nix
FLAKE ?= .
ARGS ?= # Extra arguments for nixos-rebuild (e.g. --verbose)

# Colors for help output
GREEN  := \033[32m
YELLOW := \033[33m
WHITE  := \033[37m
RESET  := \033[0m

# Detect hostname to select the correct configuration
DETECTED_HOST := $(shell hostname)
# Try to match detected hostname with flake outputs, otherwise default to 'homelab'
# (This is a simple heuristic; set HOST explicitly if needed: make switch HOST=myserver)
HOST ?= $(shell if grep -q "$(DETECTED_HOST)" flake.nix; then echo "$(DETECTED_HOST)"; else echo "homelab"; fi)

.PHONY: all
all: help

# ============================================================================
# Core Actions
# ============================================================================

.PHONY: switch
switch: ## Apply configuration and switch (nixos-rebuild switch)
	@echo "${GREEN}Switching system to configuration: ${YELLOW}$(HOST)${RESET}"
	sudo $(NIXOS_REBUILD) switch --flake $(FLAKE)#$(HOST) $(ARGS)

.PHONY: test
test: ## Test configuration without switching boot default (nixos-rebuild test)
	@echo "${GREEN}Testing configuration: ${YELLOW}$(HOST)${RESET}"
	sudo $(NIXOS_REBUILD) test --flake $(FLAKE)#$(HOST) $(ARGS)

.PHONY: boot
boot: ## Apply configuration on next boot (nixos-rebuild boot)
	@echo "${GREEN}Building boot configuration: ${YELLOW}$(HOST)${RESET}"
	sudo $(NIXOS_REBUILD) boot --flake $(FLAKE)#$(HOST) $(ARGS)

.PHONY: build
build: ## Build configuration only, no activation (nixos-rebuild build)
	@echo "${GREEN}Building configuration: ${YELLOW}$(HOST)${RESET}"
	$(NIXOS_REBUILD) build --flake $(FLAKE)#$(HOST) $(ARGS)

.PHONY: dry-run
dry-run: ## Show what would happen (nixos-rebuild dry-build)
	@echo "${GREEN}Dry run build: ${YELLOW}$(HOST)${RESET}"
	$(NIXOS_REBUILD) dry-build --flake $(FLAKE)#$(HOST) $(ARGS)

# ============================================================================
# Maintenance
# ============================================================================

.PHONY: update
update: ## Update flake inputs (nix flake update)
	@echo "${GREEN}Updating flake inputs...${RESET}"
	$(NIX) flake update

.PHONY: upgrade
upgrade: update switch ## Update inputs and switch to new configuration
	@echo "${GREEN}System upgraded.${RESET}"

.PHONY: history
history: ## Show NixOS generation history
	nix-env --list-generations --profile /nix/var/nix/profiles/system

.PHONY: gc
gc: ## Garbage collect old generations (older than 7d)
	@echo "${GREEN}Collecting garbage (older than 7d)...${RESET}"
	sudo nix-collect-garbage --delete-older-than 7d

.PHONY: clean
clean: ## Hard cleanup: GC + store optimization
	@echo "${GREEN}Deep cleaning...${RESET}"
	sudo nix-collect-garbage -d
	@echo "${GREEN}Optimizing store...${RESET}"
	sudo nix-store --optimize

# ============================================================================
# Flake Tools
# ============================================================================

.PHONY: check
check: ## Check flake for errors
	@echo "${GREEN}Checking flake...${RESET}"
	$(NIX) flake check

.PHONY: show
show: ## Show flake outputs
	$(NIX) flake show

.PHONY: fmt
fmt: ## Format nix files
	@echo "${GREEN}Formatting...${RESET}"
	$(NIX) fmt

# ============================================================================
# Development
# ============================================================================

.PHONY: vm
vm: ## Build and run a VM of the configuration
	@echo "${GREEN}Building VM for ${YELLOW}$(HOST)${RESET}"
	$(NIXOS_REBUILD) build-vm --flake $(FLAKE)#$(HOST)
	@echo "${GREEN}VM built. Run: ${YELLOW}./result/bin/run-$(HOST)-vm${RESET}"

.PHONY: repl
repl: ## Start Nix REPL with flake context
	$(NIX) repl --file flake.nix

.PHONY: debug
debug: ## Show detected make variables
	@echo "${YELLOW}Detected Host:${RESET} $(DETECTED_HOST)"
	@echo "${YELLOW}Target Host:${RESET}   $(HOST)"
	@echo "${YELLOW}Flake Path:${RESET}    $(FLAKE)"

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target] [HOST=hostname]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
