ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_GALAXY ?= ansible-galaxy
ANSIBLE_LINT ?= ansible-lint
YAMLLINT ?= yamllint
PLAYBOOK := playbooks/setup.yml
VAULT_FILE := inventories/production/group_vars/vault.yml
VAULT_EXAMPLE := inventories/production/group_vars/vault.yml.example

.PHONY: deps vault-init vault-encrypt setup lint

deps:
	$(ANSIBLE_GALAXY) collection install -r requirements.yml

vault-init:
	@test ! -e $(VAULT_FILE) || (echo "$(VAULT_FILE) already exists" >&2; exit 1)
	cp $(VAULT_EXAMPLE) $(VAULT_FILE)
	@echo "Edit $(VAULT_FILE) with a unique strong password, then run make vault-encrypt"

vault-encrypt:
	$(ANSIBLE_PLAYBOOK) --version >/dev/null
	ansible-vault encrypt $(VAULT_FILE)

setup:
	@test -n "$(VPS_HOST)" || (echo "Usage: make setup VPS_HOST=203.0.113.10" >&2; exit 2)
	$(ANSIBLE_PLAYBOOK) -i inventories/production/hosts.yml $(PLAYBOOK) --ask-vault-pass -e ansible_host=$(VPS_HOST)

lint:
	$(ANSIBLE_LINT)
	$(YAMLLINT) .
