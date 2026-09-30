# Config-Based Arch Workspace

**Level:** intermediate  ·  **Playground:** Arch Linux Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-arch-linux)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```plain
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: config-based-arch-workspace      
title: Config-Based Arch Workspace      
playground: Arch Linux
playground_link: https://kodekloud.com/playgrounds/playground-arch-linux                        
difficulty: intermediate                   
estimated_minutes: 45                      
tags:                                      
  - arch-linux
  - version-management
  - terraform
  - tooling
skills:                                    
  - linux package management
  - environment isolation
  - config-based versioning
prerequisites:                             
  - Basic Linux command line
  - Understanding of infrastructure as code (IaC) versioning
---

# Config-Based Arch Workspace

## Scenario
As a Platform Engineer, you manage your infrastructure on **Arch Linux**. Because Arch uses a rolling-release model, it constantly updates your global tools to their absolute latest versions, which is fantastic for building modern, greenfield systems.

However, you also maintain a **legacy billing system** that relies on an older, strictly locked version of Terraform (`v1.1.5`). If you accidentally run a deployment using your system's bleeding-edge tools, you will corrupt the infrastructure state file and cause a production outage. 

To solve this, you will use a universal version manager (`mise`). It acts as an intelligent safety net: your workstation runs cutting-edge tools globally, but the moment you step into your legacy project folder, it automatically downshifts to the older version.

## What you'll build
You will bootstrap a secure Arch Linux environment from scratch, install `mise` in user space, set a cutting-edge global default, and create an isolated project directory that locks Terraform to `v1.1.5` using a local configuration file.

## Learning objectives
By the end you will be able to:
- Bootstrap and securely configure a fresh Arch Linux environment.
- Install and configure a dynamic version manager (`mise`) via the shell.
- Globally install bleeding-edge DevOps tools while securely pinning legacy versions in isolated directories.
- Automatically resolve tool versions based on your current working directory.

## Prerequisites
- Playground: **Arch Linux** (open it before starting)

## Steps

### Task 1 — Fix Security Keys, Upgrade, and Bootstrap
Initialize the local trust database, perform a full system upgrade, and create a secure, unprivileged user environment.

```bash
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
```
> **Why:** It is dangerous to run builds and daily operations as the root user. This bootstraps the system with the latest Arch keyring and drops you into a secure, unprivileged `engineer` user account with sudo access.

### Task 2 — Install the Version Manager
Install `mise` to manage infrastructure tool versions dynamically across different project directories.

```bash
# 1. Download and Install the Binary:
curl https://mise.run | sh

# 2. Source the Execution Script:
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# 3. Reload the Shell:
source ~/.bashrc

# 4. Verify Installation:
mise --version
```
> **Why:** Integrating the version manager directly into your `.bashrc` allows it to intercept commands like `terraform` and seamlessly route them to the correct binary based on your current directory's configuration.

### Task 3 — Install the Terraform Versions
Download the required versions of Terraform to your local machine.

```bash
# 1. Download and Set the Global Default:
mise use --global terraform@latest

# 2. Download the Project-Specific Version:
mise install terraform@1.1.5
```
> **Why:** This establishes your workstation's baseline. Anywhere on your system, you will use the absolute latest version of Terraform, but the older v1.1.5 is now cached and available for legacy projects.

### Task 4 — Implement Config-Based Pinning
Create an isolated project workspace to lock down required tool versions via configuration.

```bash
# 1. Create the Project Workspace:
mkdir ~/legacy-billing-system
cd ~/legacy-billing-system

# 2. Pin the Local Version:
mise use terraform@1.1.5

# 3. Verify Configuration:
cat mise.toml
```
> **Why:** The `mise use` command generates a local `mise.toml` file (the modern equivalent of `.tool-versions`). This file explicitly declares that any command run inside this folder must strictly use Terraform 1.1.5.

## Validation
Run the following commands to validate that the environment correctly switches versions depending on your active directory, proving your global environment is isolated from your legacy projects.

```bash
# 1. Test the Project Environment (Config-Based Pinning)
cd ~/legacy-billing-system
terraform version

# 2. Test Global Isolation
cd ~
terraform version
```

Expected result:
- [ ] **Version Manager Initialization:** The `mise` version manager is correctly installed and successfully sourced in the shell configuration so that it resolves natively.
- [ ] **Config-Based Pinning:** Inside `~/legacy-billing-system`, a configuration file (`mise.toml`) exists, overriding the system's bleeding-edge defaults.
- [ ] **Dynamic Version Resolution:** When executing `terraform version` directly inside the project directory, the system outputs `Terraform v1.1.5`.
- [ ] **Environment Isolation:** After navigating away from the project and back to the main home directory (`cd ~`), the `terraform version` command immediately reverts to the latest available release, proving the configuration is strictly isolated.

## References & further learning
- `mise` (mise-en-place) Documentation: https://mise.jdx.dev/
- Arch Linux pacman/keyring Guide: https://wiki.archlinux.org/title/Pacman/Package_signing
- Arch Linux Users and Groups Guide: https://wiki.archlinux.org/title/Users_and_groups
```
