# Simple Monitoring Stack 🎯

**Objective:** Minimal viable stack, easy to install and maintain.

**Components:** InfluxDB + Telegraf + Prometheus + Node Exporter

**Complexity:** 4/10 (vs. 8/10 for the full stack)

**Estimated Time:** 1–2 days max

---

## 📁 Simplified Structure

```
ansible-monitoring-simple/
├── ansible.cfg
├── site.yml
├── inventory/
│   └── hosts.ini
├── group_vars/
│   └── all.yml
├── roles/
│   ├── common/
│   │   └── tasks/main.yml
│   ├── telegraf/
│   ├── node_exporter/
│   ├── prometheus/
│   └── influxdb/
└── Vagrantfile       # For local Docker testing
```

---

## 🔧 Configuration Files

### `ansible.cfg`

```ini
[defaults]
inventory = inventory/hosts.ini
host_key_checking = false
timeout = 30
gather_facts = true
remote_user = ansible

[privilege_escalation]
become = true
become_method = sudo
```

### `group_vars/all.yml`

```yaml
---
# Versions (LTS)
telegraf_version: "1.28"
prometheus_version: "2.47.0"
node_exporter_version: "1.6.1"
influxdb_version: "1.8.10"

# Ports
prometheus_port: 9090
node_exporter_port: 9100
influxdb_port: 8086
telegraf_port: 8125

# Basic settings
cluster_name: "monitoring"
environment: "production"
timezone: "Europe/Madrid"

# InfluxDB specifics
influxdb_database: "telegraf"
influxdb_retention: "30d"

# Service users
prometheus_user: "prometheus"
telegraf_user: "telegraf"
influxdb_user: "influxdb"
```

### `inventory/hosts.ini`

```ini
[telegraf_servers]
web01 ansible_host=10.0.1.10
web02 ansible_host=10.0.1.11
db01  ansible_host=10.0.1.20

[node_exporter_servers]
web01     ansible_host=10.0.1.10
web02     ansible_host=10.0.1.11
db01      ansible_host=10.0.1.20
monitor01 ansible_host=10.0.1.30

[prometheus]
monitor01 ansible_host=10.0.1.30

[influxdb]
monitor01 ansible_host=10.0.1.30

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

### `site.yml`

```yaml
---
- name: Base setup on all hosts
  hosts: all
  become: yes
  roles:
    - common

- name: Install InfluxDB
  hosts: influxdb
  become: yes
  roles:
    - influxdb

- name: Install Telegraf
  hosts: telegraf_servers
  become: yes
  roles:
    - telegraf

- name: Install Node Exporter
  hosts: node_exporter_servers
  become: yes
  roles:
    - node_exporter

- name: Install Prometheus
  hosts: prometheus
  become: yes
  roles:
    - prometheus

- name: Verify services
  hosts: all
  tasks:
    - name: Check HTTP endpoints
      uri:
        url: "{{ item }}"
        method: GET
      ignore_errors: yes
      loop:
        - "http://{{ ansible_default_ipv4.address }}:{{ prometheus_port }}"
        - "http://{{ ansible_default_ipv4.address }}:{{ influxdb_port }}/ping"
        - "http://{{ ansible_default_ipv4.address }}:{{ node_exporter_port }}/metrics"
```

---

## 🚀 Quick Start

### 1️⃣ Preparation

```bash
git clone <repo-url> ansible-monitoring-simple
cd ansible-monitoring-simple

# Edit with your real IPs:
nano inventory/hosts.ini

# (Optional) Adjust variables:
nano group_vars/all.yml
```

### 2️⃣ Production Deployment

```bash
ansible-playbook site.yml -i inventory/hosts.ini
```

### 3️⃣ Verification

```bash
ansible all -i inventory/hosts.ini -m ping
curl http://10.0.1.30:9090/targets
curl http://10.0.1.30:8086/ping
```

---

## 🧪 Local Testing with Vagrant + Docker (Optional)

You can quickly spin up a full test environment locally using the included Vagrantfile and Docker. Simply:

```bash
vagrant destroy -f           # clean previous run
vagrant up --provider=docker # launch containers
ansible-playbook site.yml -i inventory/vagrant.ini
vagrant destroy -f           # teardown
```

For full step-by-step details, refer to the “Local Testing” section in Quick Start above.

## ✅ Why This Stack??

* **No Grafana / AlertManager** → Simpler, fewer dependencies
* **Minimal configuration** → Quick rollout
* **Local Vagrant testing** → Mirror real environment in minutes
* **Lightweight** → Easy to maintain and scale

**Complexity**: 4/10
**Time**: 1–2 days

---

**Ready to monitor your infrastructure with simplicity!**
