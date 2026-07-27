INVENTORY := inventory.yaml
PLAYBOOKS := core.yaml pve.yaml lxc-bootstrap.yaml

.PHONY: help install lint syntax check check-core check-pve run-core run-pve run bootstrap-lxc

help:
	@echo "Targets:"
	@echo "  install       Install pinned Python deps (requirements.txt)"
	@echo "  lint          Run ansible-lint"
	@echo "  syntax        Syntax-check all playbooks"
	@echo "  check         Dry-run (--check --diff) all playbooks"
	@echo "  check-core    Dry-run (--check --diff) core.yaml only"
	@echo "  check-pve     Dry-run (--check --diff) pve.yaml only"
	@echo "  run-core      Apply core.yaml for real"
	@echo "  run-pve       Apply pve.yaml for real"
	@echo "  run           Apply all playbooks for real"
	@echo "  bootstrap-lxc Bootstrap an existing LXC (PVE_HOST=... required; prompts for CTID/Tailscale auth key if not given)"

install:
	pip install -r requirements.txt

lint:
	ansible-lint

syntax:
	@for playbook in $(PLAYBOOKS); do \
		ansible-playbook -i $(INVENTORY) $$playbook --syntax-check; \
	done

check: check-core check-pve

check-core:
	ansible-playbook -i $(INVENTORY) core.yaml --check --diff

check-pve:
	ansible-playbook -i $(INVENTORY) pve.yaml --check --diff

run-core:
	ansible-playbook -i $(INVENTORY) core.yaml

run-pve:
	ansible-playbook -i $(INVENTORY) pve.yaml

run: run-core run-pve

bootstrap-lxc:
ifndef PVE_HOST
	$(error PVE_HOST is required, e.g. make bootstrap-lxc PVE_HOST=caba-host)
endif
	@ctid="$(CTID)"; \
	if [ -z "$$ctid" ]; then \
		read -p "Container ID (CTID) to bootstrap on $(PVE_HOST): " ctid; \
	fi; \
	if [ -z "$$ctid" ]; then \
		echo "CTID is required" >&2; \
		exit 1; \
	fi; \
	tskey="$(TS_AUTHKEY)"; \
	if [ -z "$$tskey" ]; then \
		read -s -p "Tailscale auth key (blank to skip joining the tailnet now): " tskey; \
		echo; \
	fi; \
	ansible-playbook -i $(INVENTORY) lxc-bootstrap.yaml \
		-e "lxc_pve_host=$(PVE_HOST) lxc_prepare_ctid=$$ctid lxc_bootstrap_tailscale_authkey=$$tskey"
