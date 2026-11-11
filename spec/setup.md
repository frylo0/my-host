Готовый, красивый и безопасный сетап для вашего публичного репозитория **host-my-projects** на GitHub.  
Структура проекта спроектирована так, чтобы код можно было смело выставлять в портфолио: пароли вынесены в зашифрованные файлы (ansible-vault), а сам деплой поднимает инфраструктуру и готовит сервер в одну команду.

### **Структура файлов в репозитории host-my-projects**

Создайте на GitHub публичный репозиторий со следующей структурой файлов:  
`host-my-projects/`  
`├── inventory.ini`  
`├── playbooks/`  
`│   └── setup.yml`  
`├── files/`  
`│   └── docker-compose.infra.yml`  
`└── group_vars/`  
    `└── all/`  
        `├── vault.yml        <-- Секреты (будут зашифрованы)`  
        `└── vars.yml         <-- Несекретные переменные`

### **Шаг 1\. Конфигурация файлов (без секретов)**

#### **1\. inventory.ini**

Укажите ваш домен или оставьте плейсхолдер под IP (в реальной работе IP можно передавать через переменную):  
`[vps]`  
`my-production-server ansible_host=YOUR_VPS_IP ansible_user=root`

#### **2\. group\_vars/all/vars.yml**

Несекретные параметры (имя пользователя для деплоя, порты и т.д.):  
`---`  
`deploy_user: "deployer"`  
`infra_dir: "/opt/infra"`

#### **3\. files/docker-compose.infra.yml**

Инфраструктурный компоуз (Caddy \+ общие базы):  
`version: '3.8'`

`services:`  
  `caddy:`  
    `image: lucaslorentz/caddy-docker-proxy:alpine`  
    `container_name: caddy-proxy`  
    `restart: unless-stopped`  
    `ports:`  
      `- "80:80"`  
      `- "443:443"`  
    `volumes:`  
      `- /var/run/docker.sock:/var/run/docker.sock`  
      `- caddy_data:/data`  
      `- caddy_config:/config`  
    `networks:`  
      `- web-network`

  `mysql:`  
    `image: mariadb:10.11`  
    `container_name: shared-mysql`  
    `restart: unless-stopped`  
    `environment:`  
      `MYSQL_ROOT_PASSWORD: "{{ mysql_root_password }}"`  
    `volumes:`  
      `- mysql_data:/var/lib/mysql`  
    `networks:`  
      `- web-network`

  `mongo:`  
    `image: mongo:6.0`  
    `container_name: shared-mongo`  
    `restart: unless-stopped`  
    `volumes:`  
      `- mongo_data:/data/db`  
    `networks:`  
      `- web-network`

`volumes:`  
  `caddy_data:`  
  `caddy_config:`  
  `mysql_data:`  
  `mongo_data:`

`networks:`  
  `web-network:`  
    `external: true`

### **Шаг 2\. Безопасность и шифрование паролей (Ansible Vault)**

Чтобы не светить пароли от базы данных в публичном репо, используем встроенный менеджер секретов Ansible.

> 1. Создайте файл с секретами:  
>    `nano group_vars/all/vault.yml`

> 2. Впишите туда реальные пароли:  
>    `---`  
>    `mysql_root_password: "SuperSecretPassword123!"`

> 3. **Зашифруйте этот файл** командой Ansible (она попросит придумать мастер-пароль):  
>    `ansible-vault encrypt group_vars/all/vault.yml`  
>    *Теперь файл превратится в зашифрованную кашицу, которую можно смело пушить на GitHub. Расшифровать его сможет только тот, у кого есть ваш пароль.*

### **Шаг 3\. Написание Плейбука (playbooks/setup.yml)**

Этот скрипт делает всю работу на чистом сервере: ставит Docker, заводит безопасного юзера, переносит SSH-ключ, создает сеть и поднимает инфраструктуру.  
`---`  
`- name: Setup VPS Infrastructure & Docker`  
  `hosts: vps`  
  `become: yes`

  `tasks:`  
    `- name: Install Docker via official script`  
      `shell: curl -fsSL https://get.docker.com | sh`  
      `args:`  
        `creates: /usr/bin/docker`

    `- name: Create deployer user`  
      `user:`  
        `name: "{{ deploy_user }}"`  
        `shell: /bin/bash`  
        `groups: docker`  
        `append: yes`

    `- name: Create .ssh directory for deployer`  
      `file:`  
        `path: "/home/{{ deploy_user }}/.ssh"`  
        `state: directory`  
        `owner: "{{ deploy_user }}"`  
        `group: "{{ deploy_user }}"`  
        `mode: '0700'`

    `- name: Copy root authorized_keys to deployer for local docker context access`  
      `copy:`  
        `src: /root/.ssh/authorized_keys`  
        `dest: "/home/{{ deploy_user }}/.ssh/authorized_keys"`  
        `remote_src: yes`  
        `owner: "{{ deploy_user }}"`  
        `group: "{{ deploy_user }}"`  
        `mode: '0600'`

    `- name: Create external docker network`  
      `shell: docker network create web-network`  
      `register: net_result`  
      `failed_when: net_result.rc != 0 and 'already exists' not in net_result.stderr`

    `- name: Create infrastructure directory`  
      `file:`  
        `path: "{{ infra_dir }}"`  
        `state: directory`  
        `mode: '0755'`

    `- name: Copy infrastructure docker-compose`  
      `copy:`  
        `src: ../files/docker-compose.infra.yml`  
        `dest: "{{ infra_dir }}/docker-compose.yml"`

    `- name: Start infrastructure services`  
      `shell: docker compose up -d`  
      `args:`  
        `chdir: "{{ infra_dir }}"`

### **Шаг 4\. Как запускать это из портфолио / с локальной машины**

Убедитесь, что у вас установлен Ansible (sudo apt install ansible или через pip).

> 1. Склонируйте ваш репозиторий (или откройте локально).  
> 2. Запустите плейбук, передав файл с паролем (--ask-vault-pass спросит ваш мастер-пароль от vault):  
>    `ansible-playbook -i inventory.ini playbooks/setup.yml --ask-vault-pass`

> 3. После успешного отчета настройте docker context на локальной машине под пользователя deployer:  
>    `docker context create my-vps --docker "host=ssh://deployer@YOUR_VPS_IP"`  
>    `docker context use my-vps`

Всё\! Сервер полностью настроен, репозиторий выглядит профессионально, код чистый, секреты под надежным шифрованием, а вы можете с гордостью кидать ссылку на репо работодателям.