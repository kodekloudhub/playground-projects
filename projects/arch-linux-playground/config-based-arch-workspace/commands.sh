#!/usr/bin/env bash
set -euo pipefail

> **Why:** It is dangerous to run builds and daily operations as the root user. This bootstraps the system with the latest Arch keyring and drops you into a secure, unprivileged `engineer` user account with sudo access.

### Task 2 — Install the Version Manager
Install `mise` to manage infrastructure tool versions dynamically across different project directories.

> **Why:** Integrating the version manager directly into your `.bashrc` allows it to intercept commands like `terraform` and seamlessly route them to the correct binary based on your current directory's configuration.

### Task 3 — Install the Terraform Versions
Download the required versions of Terraform to your local machine.

> **Why:** This establishes your workstation's baseline. Anywhere on your system, you will use the absolute latest version of Terraform, but the older v1.1.5 is now cached and available for legacy projects.

### Task 4 — Implement Config-Based Pinning
Create an isolated project workspace to lock down required tool versions via configuration.

> **Why:** The `mise use` command generates a local `mise.toml` file (the modern equivalent of `.tool-versions`). This file explicitly declares that any command run inside this folder must strictly use Terraform 1.1.5.

## Validation
Run the following commands to validate that the environment correctly switches versions depending on your active directory, proving your global environment is isolated from your legacy projects.

Expected result:
- [ ] **Version Manager Initialization:** The `mise` version manager is correctly installed and successfully sourced in the shell configuration so that it resolves natively.
- [ ] **Config-Based Pinning:** Inside `~/legacy-billing-system`, a configuration file (`mise.toml`) exists, overriding the system's bleeding-edge defaults.
- [ ] **Dynamic Version Resolution:** When executing `terraform version` directly inside the project directory, the system outputs `Terraform v1.1.5`.
- [ ] **Environment Isolation:** After navigating away from the project and back to the main home directory (`cd ~`), the `terraform version` command immediately reverts to the latest available release, proving the configuration is strictly isolated.

## References & further learning
- `mise` (mise-en-place) Documentation: https://mise.jdx.dev/
- Arch Linux pacman/keyring Guide: https://wiki.archlinux.org/title/Pacman/Package_signing
- Arch Linux Users and Groups Guide: https://wiki.archlinux.org/title/Users_and_groups
