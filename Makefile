# Manages the sandbox VMs with limactl. Run `make` to see the targets.
#
# There are two VMs:
#   - $(BASE) is built one time. It installs packages and tools, then stops.
#     You never use it directly.
#   - $(NAME) is a clone of $(BASE). You run the agent in it and delete it
#     after the task. A clone starts in about 10 seconds, because it does not
#     install anything.
#
# Lima builds $(BASE) from .build/$(BASE).yaml. Make writes that file at each
# build. It uses sandbox.yaml as its Lima base template and adds each
# tools/*.sh as a provision script. This keeps the tool list out of
# sandbox.yaml, and a new script in tools/ needs no other change.

NAME ?= sandbox
BASE ?= $(NAME)-base
SRC  ?= ./scoped-credentials

TOOLS    := $(sort $(wildcard tools/*.sh))
TEMPLATE := .build/$(BASE).yaml

# Deletes a VM and does not fail when the VM does not exist.
delete-vm = limactl delete -f $(1) 2>/dev/null || true

.DEFAULT_GOAL := help

.PHONY: help validate base rebuild-base start shell copy test stop delete delete-base delete-all recreate status

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

validate: ## Make sure that the Lima configuration and the scripts are valid
	@mkdir -p $(dir $(TEMPLATE))
	@{ echo 'base:'; echo '- $(abspath sandbox.yaml)'; echo 'provision:'; \
	  for t in $(abspath $(TOOLS)); do echo '- mode: system'; echo "  file: $$t"; done; } >$(TEMPLATE)
	limactl validate $(TEMPLATE)
	@for f in provision.sh tests/hardening.sh $(TOOLS); do bash -n $$f || exit 1; done

base: validate ## Build the base VM if it does not exist, then stop it
	@if ! limactl list -q | grep -qx '$(BASE)'; then \
		echo ">> Building $(BASE). It installs packages and tools and takes a few minutes."; \
		echo ">> Lima prints nothing while it waits for 'boot scripts must have finished'."; \
		limactl start --tty=false --name=$(BASE) $(TEMPLATE); \
	fi
	@if [ "$$(limactl list $(BASE) --format '{{.Status}}')" != "Stopped" ]; then \
		limactl stop $(BASE); \
	fi

rebuild-base: ## Delete the base VM and build it again (gets updates)
	$(call delete-vm,$(BASE))
	$(MAKE) base

start: ## Start the VM, or clone a new one from the base
	@if limactl list -q | grep -qx '$(NAME)'; then \
		limactl start --tty=false $(NAME); \
	else \
		$(MAKE) base && limactl clone --tty=false --start $(BASE) $(NAME); \
	fi

shell: ## Open a shell in the VM
	limactl shell $(NAME)

copy: ## Copy SRC (default ./scoped-credentials) into the VM home directory
	limactl copy -r $(SRC) $(NAME):~/

test: ## Make sure that the hardening works (runs tests/hardening.sh in the VM)
	@limactl shell $(NAME) bash -s <tests/hardening.sh

stop: ## Stop the VM and keep its disk
	limactl stop $(NAME)

delete: ## Delete the VM and its disk (keeps the base)
	limactl delete -f $(NAME)

delete-base: ## Delete the base VM and its disk (keeps the VM)
	limactl delete -f $(BASE)

delete-all: ## Delete the VM and the base VM, if they exist
	$(call delete-vm,$(NAME))
	$(call delete-vm,$(BASE))

recreate: ## Delete the VM and clone a new one from the base
	$(call delete-vm,$(NAME))
	$(MAKE) start

status: ## Show the status of the VM and the base
	limactl list $(NAME) $(BASE)
