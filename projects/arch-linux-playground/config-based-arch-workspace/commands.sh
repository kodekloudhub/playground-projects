#!/usr/bin/env bash
set -euo pipefail

# 1. Initialize the Local Keyring:
pacman-key --init

# 2. Populate the Official Keys:
pacman-key --populate archlinux

# 3. Update to the Latest Master Keyring (Press Y when prompted):
pacman -Sy archlinux-keyring

# 4. Run a Full System Upgrade & Install Build Tools (Press Y when prompted):
pacman -Syu --needed base-devel git unzip

# 5. Create an Unprivileged User & Set a Password:
useradd -m -G wheel engineer
echo "engineer:engineer" | chpasswd

# 6. Configure Sudo Access:
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# 7. Drop Root Privileges:
su - engineer

# 1. Download and Install the Binary:
curl https://mise.run | sh

# 2. Source the Execution Script:
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# 3. Reload the Shell:
source ~/.bashrc

# 4. Verify Installation:
mise --version

# 1. Download and Set the Global Default:
mise use --global terraform@latest

# 2. Download the Project-Specific Version:
mise install terraform@1.1.5

# 1. Create the Project Workspace:
mkdir ~/legacy-billing-system
cd ~/legacy-billing-system

# 2. Pin the Local Version:
mise use terraform@1.1.5

# 3. Verify Configuration:
cat mise.toml

# 1. Test the Project Environment (Config-Based Pinning)
cd ~/legacy-billing-system
terraform version

# 2. Test Global Isolation
cd ~
terraform version
