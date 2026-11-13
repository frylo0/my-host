# my-host

Config for VPS server to move projects faster

- [Tech stack](#tech-stack)
- [VPS setup](#vps-setup)
  - [1. Install the tools on Ubuntu](#1-install-the-tools-on-ubuntu)
  - [2. Deploy the infrastructure](#2-deploy-the-infrastructure)
  - [3. Deploy applications to the infrastructure](#3-deploy-applications-to-the-infrastructure)
  - [4. Lint the project](#4-lint-the-project)


## Tech stack

- Ansible
- Ubuntu


## VPS setup

This repository uses Ansible to install Docker and start shared Caddy, MariaDB, and MongoDB services on an Ubuntu/Debian VPS. Run these commands on your Ubuntu control machine (your laptop or workstation), not on the VPS.


### 1. Install the tools on Ubuntu

Install Git, Make, Python tooling, Ansible, and the linters:

```sh
sudo apt update
sudo apt install -y git make python3 python3-pip pipx
pipx ensurepath
```

Open a new terminal so the pipx path is active, then install Ansible and lint tools in isolated environments:

```sh
pipx install --include-deps ansible
pipx install ansible-lint
pipx install yamllint
```

Clone the repo and install the collections pinned in `requirements.yml`:

```sh
git clone https://github.com/YOUR_GITHUB_USER/my-host.git
cd my-host
make deps
```

Generate SSH keypairs: `ansroot` and `deployer`, install the ansroot public key on the VPS, and write the deployer public key into the inventory settings:

```sh
make ssh-keys VPS_HOST=203.0.113.42
```


### 2. Deploy the infrastructure

Create the local vault file, edit it to set a unique strong MariaDB root password, then encrypt it. The vault password is prompted interactively and must be stored safely outside this repository:

```sh
make vault-init
vi inventories/production/group_vars/all/vault.yml
make vault-encrypt
```

Provision the VPS by passing its real IP address to Make. Example:

```sh
make setup VPS_HOST=203.0.113.42
```

> `203.0.113.42` is a documentation-only example address; replace it with your VPS IPO.


### 3. Deploy applications to the infrastructure

Deploy from each app's own local project directory. Docker Compose sends the local build context to the VPS over SSH, builds the image there, and starts/replaces the service; you do not need to push images to GitHub/GitLab registries or SSH in to run Compose manually. The VPS must have the `deployer` SSH key configured as described above.

Create a Docker context once on your local machine (replace the IP):

```sh
docker context create my-vps --docker "host=ssh://deployer@203.0.113.42"
```

In each app repository, add a Compose file and a `Makefile` deploy target. For example:

```makefile
.PHONY: deploy
deploy:
	docker --context my-vps compose up -d --build
```

Now deploy code changes from that app's directory with:

```sh
make deploy
```

The app's `compose.yaml` should attach its service to the shared network and provide Caddy labels. Example for a React static image (Dockerfile copies `dist/` into nginx):

```yaml
services:
  app:
    build: .
    restart: unless-stopped
    networks: [web-network]
    labels:
      caddy: app.example.com
      caddy.reverse_proxy: "{{upstreams 80}}"
networks:
  web-network:
    external: true
```

Next.js Compose example (the app image must run its production server on port 3000):

```yaml
services:
  app:
    build: .
    restart: unless-stopped
    networks: [web-network]
    labels:
      caddy: next.example.com
      caddy.reverse_proxy: "{{upstreams 3000}}"
networks:
  web-network:
    external: true
```

ntfy Compose example using the public upstream image and persistent cache:

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    command: serve
    restart: unless-stopped
    volumes:
      - ntfy-cache:/var/cache/ntfy
    networks: [web-network]
    labels:
      caddy: notify.example.com
      caddy.reverse_proxy: "{{upstreams 80}}"
volumes:
  ntfy-cache:
networks:
  web-network:
    external: true
```

In all cases, attach to `web-network`, do not publish app ports on the VPS, and configure authentication and backups for stateful public services.


### 4. Lint the project

Run the configured Ansible and YAML lint checks from the repository root:

```sh
make lint
```
