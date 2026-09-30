# Automating Web Deployments with Ansible

**Level:** intermediate  ·  **Playground:** Ansible Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-ansible)** — open it, then copy the files below.

## Files in this project
- [`ansible.cfg`](./ansible.cfg)
- [`deploy.yml`](./deploy.yml)
- [`group_vars/webservers.yml`](./group_vars/webservers.yml)
- [`inventory`](./inventory)
- [`templates/index.html.j2`](./templates/index.html.j2)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A digital marketing agency frequently spins up new web servers to host lightweight client landing pages. Currently, developers manually SSH into each new server using root passwords to install software and upload HTML files. This approach is unscalable, error-prone, and a security risk. The DevOps Lead has mandated that all new server provisioning must be automated using Ansible. You must set up the environment from scratch and configure a set of blank target servers into identical, production-ready web hosts.

## What you'll build
You will configure an Ansible controller workspace from scratch following Infrastructure as Code (IaC) best practices. This includes separating connection credentials into a `group_vars` file away from your main inventory, applying custom configuration in `ansible.cfg`, and creating a Jinja2 template. Finally, you will author an idempotent playbook utilizing Fully Qualified Collection Names (FQCNs) to deploy Nginx, inject the dynamic template, and establish a baseline application user across all target nodes. 

## Learning objectives
By the end you will be able to:
- Establish a best-practice Ansible directory structure for inventory and variable management.
- Securely scope connection and authentication variables using `group_vars`.
- Author idempotent Ansible playbooks utilizing precise Fully Qualified Collection Names (FQCNs).
- Dynamically template configuration files and HTML pages using Jinja2 variables.
- Execute fleet-wide configuration changes and Day-2 operations seamlessly.

## Prerequisites
- Playground: **Ansible** (open it before starting)

## Steps

### Task 1 — Configure the Ansible Environment
First, create the necessary directory structure, then define your configuration, inventory, and group variables.

```bash
cd /root/playbooks
mkdir -p group_vars templates
```

```bash
cat << 'EOF' > ansible.cfg
[defaults]
inventory = ./inventory
host_key_checking = False
stdout_callback = yaml
deprecation_warnings = False
interpreter_python = auto_silent
EOF
```

```bash
cat << 'EOF' > inventory
[webservers]
web1
web2
EOF
```

```bash
cat << 'EOF' > group_vars/webservers.yml
---
ansible_user: root
ansible_password: Passw0rd
ansible_connection: ssh
EOF
```
> **Why:** Separating your credentials into `group_vars` keeps your inventory clean and secure. The `ansible.cfg` streamlines execution in this sandbox by explicitly setting the inventory path and disabling host key checking.

### Task 2 — Build the Dynamic Template and Playbook
Create the Jinja2 template for the landing page and the declarative playbook to deploy the infrastructure.

```bash
cat << 'EOF' > templates/index.html.j2
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to {{ ansible_hostname }}</title>
</head>
<body>
    <h1>Successfully provisioned via Ansible</h1>
    <p>This server is: <strong>{{ ansible_hostname }}</strong></p>
    <p>OS Family: {{ ansible_os_family }}</p>
</body>
</html>
EOF
```

```bash
cat << 'EOF' > deploy.yml
---
- name: Bootstrap Web Tier
  hosts: webservers
  become: yes
  tasks:
    - name: Ensure Nginx is installed
      ansible.builtin.package:
        name: nginx
        state: present

    - name: Remove default Nginx Debian page
      ansible.builtin.file:
        path: /var/www/html/index.nginx-debian.html
        state: absent

    - name: Deploy dynamic index.html template
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /var/www/html/index.html
        mode: '0644'

    - name: Ensure Nginx service is started and enabled
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: yes

    - name: Create baseline deployer user
      ansible.builtin.user:
        name: deployer
        state: present
        create_home: yes
        shell: /bin/bash
EOF
```
> **Why:** Playbooks declare the desired state of the targets. Using Fully Qualified Collection Names (e.g., `ansible.builtin.package`) ensures module accuracy, while Jinja2 variables like `{{ ansible_hostname }}` allow identical code to yield custom results per server.

### Task 3 — Test Connection and Execute Deployment
Verify the controller can communicate with the targets, then run the configuration playbook.

```bash
# 1. Verify connectivity using an ad-hoc ping
ansible webservers -m ping
```

```bash
# 2. Deploy the infrastructure
ansible-playbook deploy.yml
```
> **Why:** The ad-hoc ping validates your `group_vars` credentials before executing the heavy lifting. The playbook execution will show `changed` statuses as it installs and configures Nginx across the fleet.

### Task 4 — Perform Day-2 Operations (Fleet-Wide Rollout)
In the real world, applications change constantly. Simulate pushing out a new version of the landing page by modifying the template and rerunning the playbook.

```bash
cat << 'EOF' > templates/index.html.j2
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to {{ ansible_hostname }}</title>
</head>
<body>
    <h1>Successfully provisioned via Ansible</h1>
    <p>This server is: <strong>{{ ansible_hostname }}</strong></p>
    <p>OS Family: {{ ansible_os_family }}</p>
    <h2 style="color: blue;">Application v2.0 deployed successfully!</h2>
</body>
</html>
EOF
```

```bash
ansible-playbook deploy.yml
```
> **Why:** This demonstrates idempotency. Nginx and the user creation will return `ok` because they are already in the desired state, but the template task will return `changed` because Ansible detected the updated file.

## Validation
Run the following commands directly from your controller terminal to verify your infrastructure state and ensure best practices were met.

```bash
# 1. Verify the Web Application Delivery (Checking for v2.0 update)
curl http://web1
curl http://web2
```

```bash
# 2. Verify Absolute Idempotency (Run playbook a third time)
ansible-playbook deploy.yml
```

```bash
# 3. Verify the Baseline User Account Creation
ansible webservers -a "id deployer"
```

Expected result:
- [ ] You securely separated connection credentials into `group_vars/webservers.yml` rather than placing them directly in the inventory file.
- [ ] Your `deploy.yml` playbook uses FQCNs (`ansible.builtin.*`) for all tasks.
- [ ] The `curl` commands return an HTML page displaying each node's distinct hostname alongside the updated `<h2 style="color: blue;">Application v2.0 deployed successfully!</h2>` banner.
- [ ] Running the exact same playbook multiple times results in `changed=0`, proving complete idempotency.
- [ ] The ad-hoc command `id deployer` returns standard user group information from both `web1` and `web2`, confirming the baseline user exists.

## References & further learning
- Ansible Playbooks Documentation: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html
- Understanding Privilege Escalation (`become`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
- KodeKloud course: Learn Ansible Basics - Beginners Course: https://kodekloud.com/courses/learn-ansible-basics-beginners-course
