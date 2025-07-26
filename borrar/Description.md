# Estructura mejorada del proyecto

# group_vars/all.yml
---
# Versiones centralizadas
node_exporter_version: "1.5.0"
prometheus_version: "2.45.0"
telegraf_version: "1.25.0"

# Configuración de red
prometheus_port: 9090
node_exporter_port: 9100
grafana_port: 3000

# Directorios base
base_install_dir: "/opt"
base_config_dir: "/etc"
base_data_dir: "/var/lib"

# Usuarios del sistema
prometheus_user: "prometheus"
telegraf_user: "telegraf"
grafana_user: "grafana"

# Configuración de backup
backup_enabled: true
backup_retention_days: 7

# roles/common/tasks/main.yml
---
- name: Update package cache
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Install common packages
  apt:
    name:
      - wget
      - curl
      - unzip
      - htop
      - vim
    state: present

- name: Configure timezone
  timezone:
    name: "{{ timezone | default('UTC') }}"

# roles/prometheus/tasks/main.yml
---
- name: Create prometheus user
  user:
    name: "{{ prometheus_user }}"
    system: yes
    shell: /bin/false
    home: "{{ base_data_dir }}/prometheus"
    createhome: yes

- name: Create prometheus directories
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ prometheus_user }}"
    group: "{{ prometheus_user }}"
    mode: '0755'
  loop:
    - "{{ base_data_dir }}/prometheus"
    - "{{ base_config_dir }}/prometheus"
    - "{{ base_config_dir }}/prometheus/rules"

- name: Check if Prometheus is already installed
  stat:
    path: "{{ base_install_dir }}/prometheus-{{ prometheus_version }}"
  register: prometheus_installed

- name: Download Prometheus
  get_url:
    url: "https://github.com/prometheus/prometheus/releases/download/v{{ prometheus_version }}/prometheus-{{ prometheus_version }}.linux-amd64.tar.gz"
    dest: "/tmp/prometheus-{{ prometheus_version }}.tar.gz"
    mode: '0644'
  when: not prometheus_installed.stat.exists
  retries: 3
  delay: 5

- name: Extract Prometheus
  unarchive:
    src: "/tmp/prometheus-{{ prometheus_version }}.tar.gz"
    dest: "{{ base_install_dir }}"
    remote_src: yes
    owner: "{{ prometheus_user }}"
    group: "{{ prometheus_user }}"
  when: not prometheus_installed.stat.exists

- name: Create symlink for Prometheus
  file:
    src: "{{ base_install_dir }}/prometheus-{{ prometheus_version }}.linux-amd64"
    dest: "{{ base_install_dir }}/prometheus"
    state: link
  notify: restart prometheus

- name: Deploy Prometheus configuration
  template:
    src: prometheus.yml.j2
    dest: "{{ base_config_dir }}/prometheus/prometheus.yml"
    owner: "{{ prometheus_user }}"
    group: "{{ prometheus_user }}"
    mode: '0644'
    backup: yes
  notify: restart prometheus

- name: Deploy alerting rules
  template:
    src: "{{ item }}.j2"
    dest: "{{ base_config_dir }}/prometheus/rules/{{ item }}"
    owner: "{{ prometheus_user }}"
    group: "{{ prometheus_user }}"
    mode: '0644'
  loop:
    - node_alerts.yml
    - service_alerts.yml
  notify: restart prometheus

- name: Create systemd service file
  template:
    src: prometheus.service.j2
    dest: /etc/systemd/system/prometheus.service
    mode: '0644'
  notify:
    - reload systemd
    - restart prometheus

- name: Configure firewall for Prometheus
  ufw:
    rule: allow
    port: "{{ prometheus_port }}"
    proto: tcp
  when: configure_firewall | default(true)

- name: Ensure Prometheus is running
  systemd:
    name: prometheus
    enabled: yes
    state: started
    daemon_reload: yes

- name: Setup logrotate for Prometheus
  template:
    src: prometheus.logrotate.j2
    dest: /etc/logrotate.d/prometheus
    mode: '0644'

# roles/prometheus/templates/prometheus.service.j2
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/
After=network-online.target

[Service]
Type=simple
User={{ prometheus_user }}
Group={{ prometheus_user }}
ExecStart={{ base_install_dir }}/prometheus/prometheus \
  --config.file={{ base_config_dir }}/prometheus/prometheus.yml \
  --storage.tsdb.path={{ base_data_dir }}/prometheus/ \
  --web.console.templates={{ base_install_dir }}/prometheus/consoles \
  --web.console.libraries={{ base_install_dir }}/prometheus/console_libraries \
  --web.listen-address=:{{ prometheus_port }} \
  --storage.tsdb.retention.time={{ prometheus_retention | default('30d') }}
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

# roles/prometheus/templates/prometheus.yml.j2
global:
  scrape_interval: {{ scrape_interval | default('15s') }}
  evaluation_interval: {{ evaluation_interval | default('15s') }}
  external_labels:
    cluster: '{{ cluster_name | default("main") }}'
    environment: '{{ environment | default("production") }}'

rule_files:
  - "rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:{{ prometheus_port }}']
    scrape_interval: 5s
    metrics_path: /metrics

  - job_name: 'node_exporter'
    static_configs:
      - targets: 
{% for host in groups['exporter_servers'] %}
        - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:{{ node_exporter_port }}
{% endfor %}
    scrape_interval: 10s

  - job_name: 'telegraf'
    metrics_path: '/metrics'
    static_configs:
      - targets:
{% for host in groups['telegraf_servers'] %}
        - {{ hostvars[host]['ansible_default_ipv4']['address'] }}:8125
{% endfor %}
    scrape_interval: 10s

# roles/prometheus/templates/node_alerts.yml.j2
groups:
  - name: node_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for instance {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% for instance {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk space is below 10% for {{ $labels.mountpoint }} on {{ $labels.instance }}"

# roles/node_exporter/tasks/main.yml
---
- name: Create node_exporter user
  user:
    name: node_exporter
    system: yes
    shell: /bin/false
    home: /var/lib/node_exporter
    createhome: no

- name: Check if Node Exporter is already installed
  stat:
    path: "{{ base_install_dir }}/node_exporter-{{ node_exporter_version }}"
  register: node_exporter_installed

- name: Download Node Exporter
  get_url:
    url: "https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
    dest: "/tmp/node_exporter-{{ node_exporter_version }}.tar.gz"
    mode: '0644'
  when: not node_exporter_installed.stat.exists
  retries: 3
  delay: 5

- name: Extract Node Exporter
  unarchive:
    src: "/tmp/node_exporter-{{ node_exporter_version }}.tar.gz"
    dest: "{{ base_install_dir }}"
    remote_src: yes
    owner: node_exporter
    group: node_exporter
  when: not node_exporter_installed.stat.exists

- name: Create symlink for Node Exporter
  file:
    src: "{{ base_install_dir }}/node_exporter-{{ node_exporter_version }}.linux-amd64"
    dest: "{{ base_install_dir }}/node_exporter"
    state: link
  notify: restart node_exporter

- name: Create systemd service for node_exporter
  template:
    src: node_exporter.service.j2
    dest: /etc/systemd/system/node_exporter.service
    mode: '0644'
  notify:
    - reload systemd
    - restart node_exporter

- name: Configure firewall for Node Exporter
  ufw:
    rule: allow
    port: "{{ node_exporter_port }}"
    proto: tcp
  when: configure_firewall | default(true)

- name: Ensure node_exporter is running
  systemd:
    name: node_exporter
    enabled: yes
    state: started
    daemon_reload: yes

# site.yml mejorado
---
- name: Common setup
  hosts: all
  become: yes
  roles:
    - common
  tags:
    - common

- name: Deploy Telegraf
  hosts: telegraf_servers
  become: yes
  roles:
    - telegraf
  tags:
    - telegraf

- name: Deploy Node Exporter
  hosts: exporter_servers
  become: yes
  roles:
    - node_exporter
  tags:
    - node_exporter

- name: Deploy Prometheus
  hosts: prometheus
  become: yes
  roles:
    - prometheus
  tags:
    - prometheus

- name: Deploy Grafana
  hosts: grafana
  become: yes
  roles:
    - grafana
  tags:
    - grafana

- name: Verify deployment
  hosts: all
  become: yes
  tasks:
    - name: Check service status
      systemd:
        name: "{{ item }}"
      register: service_status
      loop:
        - telegraf
        - node_exporter
        - prometheus
        - grafana-server
      when: item in group_names
      tags:
        - verify

# requirements.yml para dependencias
---
collections:
  - name: community.general
    version: ">=3.0.0"
  - name: ansible.posix
    version: ">=1.0.0"

# ansible.cfg mejorado
[defaults]
inventory = inventory/hosts.ini
roles_path = roles
host_key_checking = false
timeout = 30
forks = 5
gather_facts = true
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 86400

[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml

[privilege_escalation]
become = true
become_method = sudo
become_user = root
become_ask_pass = false