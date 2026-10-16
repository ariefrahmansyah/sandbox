NAME   ?= sandbox
BASE   ?= $(NAME)-base
CONFIG ?= sandbox.yaml
SRC    ?= ./scoped-credentials

.DEFAULT_GOAL := help

.PHONY: help validate base rebuild-base start shell copy test stop delete recreate status

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

validate: ## Validate the Lima configuration
	limactl validate $(CONFIG)

base: validate ## Build the base VM once (installs packages), then stop it
	@if ! limactl list -q | grep -qx '$(BASE)'; then \
		echo ">> Building $(BASE). It installs packages and takes about 2 minutes."; \
		echo ">> Lima prints nothing while it waits for 'boot scripts must have finished'."; \
		limactl start --tty=false --name=$(BASE) $(CONFIG); \
	fi
	@if [ "$$(limactl list $(BASE) --format '{{.Status}}')" != "Stopped" ]; then \
		limactl stop $(BASE); \
	fi

rebuild-base: ## Delete the base VM and build it again (updates packages)
	limactl delete -f $(BASE) 2>/dev/null || true
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

test: ## Make sure that the hardening works
	@limactl shell $(NAME) -- bash -c '\
		fail=0; \
		if sudo -n true 2>/dev/null; then echo "FAIL  sudo works"; fail=1; else echo "ok    sudo is blocked"; fi; \
		if [ -e ~/password ]; then echo "FAIL  ~/password exists"; fail=1; else echo "ok    ~/password does not exist"; fi; \
		err=$$(timeout 5 bash -c "</dev/tcp/192.168.5.2/53" 2>&1); \
		if echo "$$err" | grep -qi "no route to host"; then echo "ok    host is blocked"; \
		else echo "FAIL  host is not blocked: $$err"; fail=1; fi; \
		if curl -sSI -m 10 https://github.com >/dev/null; then echo "ok    internet works"; else echo "FAIL  internet does not work"; fail=1; fi; \
		exit $$fail'

stop: ## Stop the VM and keep its disk
	limactl stop $(NAME)

delete: ## Delete the VM and its disk (keeps the base)
	limactl delete -f $(NAME)

recreate: ## Delete the VM and clone a new one from the base
	limactl delete -f $(NAME) 2>/dev/null || true
	$(MAKE) start

status: ## Show the status of the VM and the base
	limactl list $(NAME) $(BASE)
