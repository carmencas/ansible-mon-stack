# ============================================================================
# GUÍA COMPLETA DE TESTING PARA ANSIBLE
# ============================================================================

# 1. TESTING BÁSICO - Validación de sintaxis
# ============================================================================

# Makefile para comandos comunes
test-syntax:
	ansible-playbook --syntax-check site.yml

test-lint:
	ansible-lint site.yml

test-dry-run:
	ansible-playbook site.yml --check --diff

# 2. TESTING CON VAGRANT (Recomendado para desarrollo)
# ============================================================================

# Vagrantfile
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Definir máquinas de test
  config.vm.define "prometheus" do |prometheus|
    prometheus.vm.box = "ubuntu/focal64"
    prometheus.vm.hostname = "prometheus-test"
    prometheus.vm.network "private_network", ip: "192.168.56.10"
    prometheus.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2
    end
  end

  config.vm.define "grafana" do |grafana|
    grafana.vm.box = "ubuntu/focal64"
    grafana.vm.hostname = "grafana-test"
    grafana.vm.network "private_network", ip: "192.168.56.11"
    grafana.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
      vb.cpus = 1
    end
  end

  config.vm.define "node1" do |node1|
    node1.vm.box = "ubuntu/focal64"
    node1.vm.hostname = "node1-test"
    node1.vm.network "private_network", ip: "192.168.56.20"
    node1.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
  end

  config.vm.define "node2" do |node2|
    node2.vm.box = "ubuntu/focal64"
    node2.vm.hostname = "node2-test"
    node2.vm.network "private_network", ip: "192.168.56.21"
    node2.vm.provider "virtualbox" do |vb|
      vb.memory = "512"
      vb.cpus = 1
    end
  end

  # Provisión con Ansible
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "site.yml"
    ansible.inventory_path = "inventory/vagrant.ini"
    ansible.limit = "all"
    ansible.verbose = "v"
  end
end

# inventory/vagrant.ini
[telegraf_servers]
192.168.56.20 ansible_user=vagrant
192.168.56.21 ansible_user=vagrant

[exporter_servers]
192.168.56.20 ansible_user=vagrant
192.168.56.21 ansible_user=vagrant

[prometheus]
192.168.56.10 ansible_user=vagrant

[grafana]
192.168.56.11 ansible_user=vagrant

# 3. TESTING CON MOLECULE (Testing framework oficial)
# ============================================================================

# requirements.txt
molecule[docker]
docker
pytest
testinfra

# molecule/default/molecule.yml
---
dependency:
  name: galaxy
driver:
  name: docker
platforms:
  - name: prometheus-instance
    image: ubuntu:20.04
    pre_build_image: true
    privileged: true
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    published_ports:
      - "9090:9090"
  - name: grafana-instance
    image: ubuntu:20.04
    pre_build_image: true
    privileged: true
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    published_ports:
      - "3000:3000"
  - name: node1-instance
    image: ubuntu:20.04
    pre_build_image: true
    privileged: true
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    published_ports:
      - "9100:9100"
provisioner:
  name: ansible
  inventory:
    host_vars:
      prometheus-instance:
        ansible_user: root
      grafana-instance:
        ansible_user: root
      node1-instance:
        ansible_user: root
verifier:
  name: testinfra

# molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: true
  pre_tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
      changed_when: false

- name: Deploy Prometheus
  hosts: prometheus-instance
  become: true
  roles:
    - prometheus

- name: Deploy Grafana
  hosts: grafana-instance
  become: true
  roles:
    - grafana

- name: Deploy Node Exporter
  hosts: node1-instance
  become: true
  roles:
    - node_exporter

# molecule/default/verify.yml
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: Example assertion
      assert:
        that: true

# 4. TESTS DE INTEGRACIÓN CON TESTINFRA
# ============================================================================

# molecule/default/tests/test_default.py
import os
import pytest
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')

def test_prometheus_service(host):
    """Test Prometheus service is running"""
    if 'prometheus' in host.ansible.get_variables()['inventory_hostname']:
        service = host.service("prometheus")
        assert service.is_running
        assert service.is_enabled

def test_prometheus_port(host):
    """Test Prometheus is listening on port 9090"""
    if 'prometheus' in host.ansible.get_variables()['inventory_hostname']:
        socket = host.socket("tcp://0.0.0.0:9090")
        assert socket.is_listening

def test_prometheus_config(host):
    """Test Prometheus configuration file exists"""
    if 'prometheus' in host.ansible.get_variables()['inventory_hostname']:
        config = host.file("/etc/prometheus/prometheus.yml")
        assert config.exists
        assert config.is_file
        assert config.user == "prometheus"
        assert config.group == "prometheus"

def test_node_exporter_service(host):
    """Test Node Exporter service is running"""
    if 'node' in host.ansible.get_variables()['inventory_hostname']:
        service = host.service("node_exporter")
        assert service.is_running
        assert service.is_enabled

def test_node_exporter_port(host):
    """Test Node Exporter is listening on port 9100"""
    if 'node' in host.ansible.get_variables()['inventory_hostname']:
        socket = host.socket("tcp://0.0.0.0:9100")
        assert socket.is_listening

def test_grafana_service(host):
    """Test Grafana service is running"""
    if 'grafana' in host.ansible.get_variables()['inventory_hostname']:
        service = host.service("grafana-server")
        assert service.is_running
        assert service.is_enabled

def test_grafana_port(host):
    """Test Grafana is listening on port 3000"""
    if 'grafana' in host.ansible.get_variables()['inventory_hostname']:
        socket = host.socket("tcp://0.0.0.0:3000")
        assert socket.is_listening

def test_users_created(host):
    """Test system users are created"""
    hostname = host.ansible.get_variables()['inventory_hostname']
    
    if 'prometheus' in hostname:
        user = host.user("prometheus")
        assert user.exists
        assert user.shell == "/bin/false"
    
    if 'node' in hostname:
        user = host.user("node_exporter")
        assert user.exists
        assert user.shell == "/bin/false"

def test_directories_created(host):
    """Test required directories exist with correct permissions"""
    hostname = host.ansible.get_variables()['inventory_hostname']
    
    if 'prometheus' in hostname:
        data_dir = host.file("/var/lib/prometheus")
        assert data_dir.exists
        assert data_dir.is_directory
        assert data_dir.user == "prometheus"
        assert data_dir.group == "prometheus"

def test_metrics_endpoints(host):
    """Test metrics endpoints are accessible"""
    hostname = host.ansible.get_variables()['inventory_hostname']
    
    if 'prometheus' in hostname:
        cmd = host.run("curl -s http://localhost:9090/metrics")
        assert cmd.rc == 0
        assert "prometheus_build_info" in cmd.stdout
    
    if 'node' in hostname:
        cmd = host.run("curl -s http://localhost:9100/metrics")
        assert cmd.rc == 0
        assert "node_cpu_seconds_total" in cmd.stdout

# 5. DOCKER COMPOSE PARA TESTING RÁPIDO
# ============================================================================

# docker-compose.test.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./test-configs/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-storage:/var/lib/grafana
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge

volumes:
  grafana-storage:

# 6. GITHUB ACTIONS PARA CI/CD
# ============================================================================

# .github/workflows/test.yml
name: Test Ansible Playbooks

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: [3.8, 3.9]

    steps:
    - uses: actions/checkout@v3

    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install ansible ansible-lint molecule[docker] docker pytest testinfra

    - name: Lint Ansible playbooks
      run: |
        ansible-lint site.yml

    - name: Test with molecule
      run: |
        molecule test

    - name: Run syntax check
      run: |
        ansible-playbook --syntax-check site.yml

# 7. SCRIPTS DE TESTING
# ============================================================================

# scripts/test.sh
#!/bin/bash

set -e

echo "🔍 Running Ansible tests..."

# Syntax check
echo "1. Syntax check..."
ansible-playbook --syntax-check site.yml

# Lint check
echo "2. Lint check..."
ansible-lint site.yml

# Dry run
echo "3. Dry run..."
ansible-playbook site.yml --check --diff

# Molecule test if available
if command -v molecule &> /dev/null; then
    echo "4. Molecule test..."
    molecule test
fi

echo "✅ All tests passed!"

# scripts/integration-test.sh
#!/bin/bash

set -e

echo "🚀 Running integration tests..."

# Start test environment
docker-compose -f docker-compose.test.yml up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Test Prometheus
echo "Testing Prometheus..."
curl -f http://localhost:9090/api/v1/query?query=up || exit 1

# Test Grafana
echo "Testing Grafana..."
curl -f http://localhost:3000/api/health || exit 1

# Test Node Exporter
echo "Testing Node Exporter..."
curl -f http://localhost:9100/metrics || exit 1

# Cleanup
docker-compose -f docker-compose.test.yml down

echo "✅ Integration tests passed!"

# 8. MAKEFILE PARA COMANDOS COMUNES
# ============================================================================

# Makefile
.PHONY: test test-syntax test-lint test-dry-run test-molecule test-integration clean

# Main test command
test: test-syntax test-lint test-dry-run

# Individual tests
test-syntax:
	@echo "🔍 Running syntax check..."
	ansible-playbook --syntax-check site.yml

test-lint:
	@echo "🔍 Running ansible-lint..."
	ansible-lint site.yml

test-dry-run:
	@echo "🔍 Running dry run..."
	ansible-playbook site.yml --check --diff -i inventory/vagrant.ini

test-molecule:
	@echo "🔍 Running molecule tests..."
	molecule test

test-integration:
	@echo "🔍 Running integration tests..."
	./scripts/integration-test.sh

# Environment management
vagrant-up:
	vagrant up

vagrant-destroy:
	vagrant destroy -f

# Docker testing
docker-test:
	docker-compose -f docker-compose.test.yml up -d
	sleep 30
	./scripts/integration-test.sh
	docker-compose -f docker-compose.test.yml down

clean:
	vagrant destroy -f
	docker-compose -f docker-compose.test.yml down -v
	molecule destroy

# 9. CONFIGURACIÓN DE PYTEST
# ============================================================================

# pytest.ini
[tool:pytest]
testpaths = molecule/default/tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short

# 10. EJEMPLO DE USO
# ============================================================================

# Para empezar a testear:

# 1. Instalación de dependencias
# pip install -r requirements.txt

# 2. Testing básico
# make test

# 3. Testing con Vagrant
# vagrant up
# ansible-playbook site.yml -i inventory/vagrant.ini

# 4. Testing con Molecule
# molecule test

# 5. Testing con Docker Compose
# make docker-test

# 6. CI/CD
# git push (ejecutará GitHub Actions automáticamente)