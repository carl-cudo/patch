#!/bin/bash
set -euo pipefail

# --- Configuration (Internal Bash Variables) ---
readonly LOG_FILE="/root/uyuni_setup.log"

# --- Pre-run Checks & Logging Setup ---
# Redirect all output to the log file and the console.
exec &> >(tee -a "$LOG_FILE")

# --- Helper Functions ---
log_action() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] - INFO: $1"; }
log_success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] - \e[32mSUCCESS\e[0m: $1"; }
log_error_exit() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] - \e[31mERROR\e[0m: $1" >&2; exit 1; }

# --- Main Script Logic ---
main() {
    log_action "Starting Uyuni server setup for OpenSUSE."
    
    # 1. System Update (on 15.4)
    log_action "Running system update on 15.4..."
    zypper --non-interactive refresh
    zypper --non-interactive update -y
    log_success "System is fully patched on 15.4."

    # 2. Automated Distribution Upgrade to 15.5
    log_action "Beginning automated upgrade to openSUSE Leap 15.5..."
    log_action "Updating all repository URLs from 15.4 to 15.5..."
    sed -i 's/15.4/15.5/g' /etc/zypp/repos.d/*.repo
    
    log_action "Refreshing repositories with 15.5 metadata..."
    zypper --non-interactive --gpg-auto-import-keys refresh
    
    log_action "Running distribution upgrade to 15.5... This will take a long time."
    zypper --non-interactive dup -y
    log_success "Successfully upgraded to openSUSE Leap 15.5."
    
    # 3. Automated Distribution Upgrade to 15.6
    log_action "Beginning automated upgrade to openSUSE Leap 15.6..."
    log_action "Updating all repository URLs from 15.5 to 15.6..."
    sed -i 's/15.5/15.6/g' /etc/zypp/repos.d/*.repo
    
    log_action "Refreshing repositories with 15.6 metadata..."
    zypper --non-interactive --gpg-auto-import-keys refresh
    
    log_action "Running distribution upgrade to 15.6... This will also take a long time."
    zypper --non-interactive dup -y
    log_success "Successfully upgraded to openSUSE Leap 15.6."

    # 4. Add Uyuni GPG Key and Repository
    # --- IMPORTANT ---
    # At the time of this writing, Uyuni officially targets 15.5. 
    # The 15.5 repo *should* work on 15.6, but if it fails, you may need
    # to find a 15.6-specific Uyuni repo URL.
    log_action "Adding Uyuni GPG key..."
    rpm --import "https://www.uyuni-project.org/keys/RPM-GPG-KEY-uyuni"
    
    log_action "Adding Uyuni repository (using 15.5 URL)..."
    zypper --non-interactive addrepo --gpgcheck \
      "https://download.opensuse.org/repositories/systemsmanagement:/Uyuni:/Stable/openSUSE_Leap_15.5/systemsmanagement:Uyuni:Stable.repo"
    
    log_action "Refreshing repositories with Uyuni..."
    zypper --non-interactive refresh
    log_success "Uyuni repository added."

    # 5. Install Uyuni Server Pattern
    log_action "Installing Uyuni server pattern..."
    zypper --non-interactive install -y patterns-uyuni_server
    log_success "Uyuni server packages installed."

    # 6. Final Instructions
    log_action "--- Script Finished ---"
    log_action "VM is ready (on Leap 15.6) and Uyuni packages are installed."
    log_action "To complete setup, SSH in as root and run:"
    log_action "  uyuni-server-setup"
}

# Execute the main function
main
