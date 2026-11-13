ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_GALAXY ?= ansible-galaxy
ANSIBLE_LINT ?= ansible-lint
YAMLLINT ?= yamllint
PLAYBOOK := playbooks/setup.yml
VAULT_FILE := inventories/production/group_vars/all/vault.yml
VAULT_EXAMPLE := inventories/production/group_vars/all/vault.yml.example
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: deps vault-init vault-encrypt ssh-keys setup lint

deps:
	$(ANSIBLE_GALAXY) collection install -r requirements.yml

vault-init:
	@mkdir -p inventories/production/group_vars/all
	@test ! -e $(VAULT_FILE) || (echo "$(VAULT_FILE) already exists" >&2; exit 1)
	cp $(VAULT_EXAMPLE) $(VAULT_FILE)
	@echo "Edit $(VAULT_FILE) with a unique strong password, then run make vault-encrypt"

vault-encrypt:
	$(ANSIBLE_PLAYBOOK) --version >/dev/null
	ansible-vault encrypt $(VAULT_FILE)

ssh-keys:
	@cd "$(ROOT_DIR)" && set -eu; \
	settings=inventories/production/group_vars/all/settings.yml; \
	if [ ! -f "$$settings" ]; then \
		echo "Error: $$settings not found; run this target from the my-host repository." >&2; \
		exit 1; \
	fi; \
	if [ -z "$(VPS_HOST)" ]; then \
		echo "Usage: make ssh-keys VPS_HOST=203.0.113.10" >&2; \
		exit 2; \
	fi; \
	grep -q '^deploy_user_ssh_public_key:' "$$settings" || { \
		echo "Error: deploy_user_ssh_public_key is missing from $$settings." >&2; \
		exit 1; \
	}; \
	ansroot_exists=0; \
	if [ -f "$$HOME/.ssh/my-vps-ansroot" ] && [ -f "$$HOME/.ssh/my-vps-ansroot.pub" ]; then \
		echo "Warning: ansroot keypair already exists; key creation and ssh-copy-id are skipped." >&2; \
		ansroot_exists=1; \
	elif [ -e "$$HOME/.ssh/my-vps-ansroot" ] || [ -e "$$HOME/.ssh/my-vps-ansroot.pub" ]; then \
		echo "Error: incomplete ansroot keypair in ~/.ssh; repair or remove it before continuing." >&2; \
		exit 1; \
	else \
		ssh-keygen -t ed25519 -f "$$HOME/.ssh/my-vps-ansroot" -C "my-vps-ansroot"; \
	fi; \
	if [ "$$ansroot_exists" -eq 0 ]; then \
		ssh-copy-id -i "$$HOME/.ssh/my-vps-ansroot.pub" "ansroot@$(VPS_HOST)"; \
	fi; \
	if [ -f "$$HOME/.ssh/my-vps-deployer" ] && [ -f "$$HOME/.ssh/my-vps-deployer.pub" ]; then \
		echo "Warning: deployer keypair already exists; key creation is skipped." >&2; \
	elif [ -e "$$HOME/.ssh/my-vps-deployer" ] || [ -e "$$HOME/.ssh/my-vps-deployer.pub" ]; then \
		echo "Error: incomplete deployer keypair in ~/.ssh; repair or remove it before continuing." >&2; \
		exit 1; \
	else \
		ssh-keygen -t ed25519 -f "$$HOME/.ssh/my-vps-deployer" -C "my-vps-deployer"; \
	fi; \
	deploy_key=$$(cat "$$HOME/.ssh/my-vps-deployer.pub"); \
	sed -i "s|^deploy_user_ssh_public_key:.*|deploy_user_ssh_public_key: \"$$deploy_key\"|" "$$settings"; \
	echo "Generated both keypairs, installed the ansroot key, and updated $$settings."

setup:
	@test -n "$(VPS_HOST)" || (echo "Usage: make setup VPS_HOST=203.0.113.10" >&2; exit 2)
	$(ANSIBLE_PLAYBOOK) -i inventories/production/hosts.yml $(PLAYBOOK) --ask-vault-pass -e ansible_host=$(VPS_HOST)

lint:
	$(ANSIBLE_LINT)
	$(YAMLLINT) .
