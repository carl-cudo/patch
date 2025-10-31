#!/bin/bash
set -euo pipefail

# --- Ansible-based Jumpbox Setup Script (Corrected for Terraform Templating) ---
# This script is intended to be used with Terraform's `templatefile` function.
# It handles the setup of a jumpbox using a locally executed Ansible playbook.

# --- Configuration (Internal Bash Variables) ---
readonly LOG_FILE="/root/ansible_setup.log"
readonly ANSIBLE_DIR="/opt/ansible-setup"
readonly PLAYBOOK_FILE="$ANSIBLE_DIR/carls_jumpbox_setup.yml"

# Variables Passed from Wrapper Script
# Read from positional arguments $1 and $2
echo "Reading variables from script arguments..."
readonly JUMPBOX_USER="$1"
readonly SSH_PUB_KEY_CONTENT="$2"

# --- Pre-run Checks & Logging Setup ---
# Redirect all output to the log file and the console.
exec &> >(tee -a "$LOG_FILE")

# Use double quotes to allow shell expansion of the function argument '$1'.
log_action() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] - INFO: $1"; }
log_success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] - \e[32mSUCCESS\e[0m: $1"; }
log_error_exit() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] - \e[31mERROR\e[0m: $1" >&2; exit 1; }

# --- Main Script Logic ---
main() {
    # Check if variables were received
    if [ -z "$JUMPBOX_USER" ] || [ -z "$SSH_PUB_KEY_CONTENT" ]; then
        log_error_exit "JUMPBOX_USER or SSH_PUB_KEY_CONTENT was not received. Aborting."
    fi

    log_action "Starting Ansible-based jumpbox setup for user: $JUMPBOX_USER."
    export DEBIAN_FRONTEND=noninteractive

    # 1. System Update and Ansible Installation
    log_action "Updating system and installing Ansible, Git, and supporting packages..."
    apt-get update -q
    apt-get upgrade -y -q
    # Using -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" to handle prompts
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ansible git python3-pip
    log_success "System updated and Ansible installed."

    log_action "Configuring system locale for UTF-8..."
    apt-get install -y -q locales
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    log_success "System locale set to en_US.UTF-8."

    # 2. Setup Ansible Directory and Files
    log_action "Setting up Ansible directory and playbook files..."
    mkdir -p "$ANSIBLE_DIR/roles"
    cd "$ANSIBLE_DIR" || log_error_exit "Failed to change to Ansible directory."

    # Create Local Inventory
    log_action "Creating local inventory file."
    echo "[jumpbox]" > inventory.ini
    echo "localhost ansible_connection=local" >> inventory.ini

    # 3. Create the Main Playbook
    # Use 'EOF' (with single quotes) to prevent shell from expanding variables inside the here-doc.
    # Ansible will handle the {{ ... }} variables.
    log_action "Creating main playbook: $PLAYBOOK_FILE."
    cat << 'EOF' > "$PLAYBOOK_FILE"
---
- name: Setup Carl's Jumpbox
  hosts: localhost
  connection: local
  become: yes

  vars:
    # These vars are passed in from the ansible-playbook command line.
    target_user: "{{ username }}"
    ssh_public_key_content: "{{ ssh_key_content }}"

  roles:
    - system_update
    - user_setup
    - install_tools
    - install_docker
EOF

    # 4. Create Role Task Files
    log_action "Creating required Ansible roles structure and tasks..."
    mkdir -p roles/{system_update/tasks,user_setup/tasks,install_tools/tasks,install_docker/tasks}

    # --- system_update Role ---
    cat << 'EOF' > roles/system_update/tasks/main.yml
---
- name: Ensure all packages are up to date
  ansible.builtin.apt:
    update_cache: yes
    upgrade: full
    autoclean: yes
  tags: update
EOF

    # --- user_setup Role ---
    cat << 'EOF' > roles/user_setup/tasks/main.yml
---
- name: Create the user '{{ target_user }}' and add to sudo
  ansible.builtin.user:
    name: "{{ target_user }}"
    state: present
    shell: /bin/bash
    groups: sudo
    append: yes

- name: Create .ssh directory for the user
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.ssh"
    state: directory
    owner: "{{ target_user }}"
    group: "{{ target_user }}"
    mode: '0700'

- name: Set up authorized_keys for SSH login
  ansible.builtin.copy:
    content: "{{ ssh_public_key_content }}"
    dest: "/home/{{ target_user }}/.ssh/authorized_keys"
    owner: "{{ target_user }}"
    group: "{{ target_user }}"
    mode: '0600'
  when: ssh_public_key_content is defined and ssh_public_key_content | length > 0
EOF

    # --- install_tools Role ---
    cat << 'EOF' > roles/install_tools/tasks/main.yml
---
- name: Install general utilities (btop and mtr)
  ansible.builtin.apt:
    name:
      - btop
      - mtr
    state: present

- name: Add Google Cloud CLI repository key
  ansible.builtin.apt_key:
    url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    state: present

- name: Add Google Cloud CLI repository
  ansible.builtin.apt_repository:
    repo: deb [arch=amd64] https://packages.cloud.google.com/apt cloud-sdk main
    state: present
    filename: google-cloud-sdk

- name: Install Google Cloud CLI
  ansible.builtin.apt:
    name: google-cloud-cli
    update_cache: yes
    state: present
EOF

    # --- install_docker Role ---
    cat << 'EOF' > roles/install_docker/tasks/main.yml
---
- name: Install dependencies for Docker repository setup
  ansible.builtin.apt:
    name:
      - ca-certificates
      - curl
      - gnupg
    state: present
    update_cache: yes

- name: Create directory for Docker GPG key
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: '0755'

- name: Add Docker's official GPG key
  ansible.builtin.apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    keyring: /etc/apt/keyrings/docker.gpg
    state: present

- name: Set up the stable Docker repository
  ansible.builtin.apt_repository:
    repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present
    filename: docker

- name: Install Docker Engine
  ansible.builtin.apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    state: present
    update_cache: yes

- name: Ensure the 'docker' group exists
  ansible.builtin.group:
    name: docker
    state: present

- name: Add user '{{ target_user }}' to the docker group
  ansible.builtin.user:
    name: "{{ target_user }}"
    groups: docker
    append: yes
EOF

    log_success "Ansible files and roles created."

    # 5. Run the Playbook
    log_action "Executing Ansible Playbook..."
    # Pass the Terraform variables into Ansible. Note the single quotes around
    # the SSH key to handle multi-line content robustly.
    ansible-playbook \
        -i inventory.ini \
        "$PLAYBOOK_FILE" \
        -e "username=$JUMPBOX_USER" \
        -e "ssh_key_content='$SSH_PUB_KEY_CONTENT'"

    # Check the exit code of the last command ($?) correctly.
    if [ $? -eq 0 ]; then
        log_success "Ansible Playbook executed successfully. Jumpbox setup complete."
    else
        log_error_exit "Ansible Playbook failed to run. Check $LOG_FILE for details."
    fi

    log_action "--- Script Finished ---"
    log_action "VM is ready. Log in as user $JUMPBOX_USER using your SSH key."
}

# Execute the main function
main
