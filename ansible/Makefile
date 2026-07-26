INVENTORY := inventory.yaml
PLAYBOOKS := core.yaml pve.yaml

.PHONY: help install lint syntax check check-core check-pve run-core run-pve run

help:
	@echo "Targets:"
	@echo "  install     Install pinned Python deps (requirements.txt)"
	@echo "  lint        Run ansible-lint"
	@echo "  syntax      Syntax-check all playbooks"
	@echo "  check       Dry-run (--check --diff) all playbooks"
	@echo "  check-core  Dry-run (--check --diff) core.yaml only"
	@echo "  check-pve   Dry-run (--check --diff) pve.yaml only"
	@echo "  run-core    Apply core.yaml for real"
	@echo "  run-pve     Apply pve.yaml for real"
	@echo "  run         Apply all playbooks for real"

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
