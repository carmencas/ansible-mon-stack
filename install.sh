#!/bin/bash
set -e

echo "=== Installing Simple Monitoring Stack ==="

# Check for Ansible
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    sudo apt update
    sudo apt install -y ansible
fi

# Verify connectivity
echo "Verifying connectivity..."
ansible all -i inventory/hosts.ini -m ping

# Run playbook
echo "Running deployment..."
ansible-playbook site.yml -i inventory/hosts.ini

echo "=== Installation Complete! ==="
echo
echo "Access URLs:"
echo "  • Prometheus: http://$(grep -A1 '\[prometheus\]' inventory/hosts.ini | tail -1 | cut -d'=' -f2):9090"
echo "  • InfluxDB: http://$(grep -A1 '\[influxdb\]' inventory/hosts.ini | tail -1 | cut -d'=' -f2):8086"
echo
echo "Verification commands:"
echo "  curl http://<your-server>:9090/targets"
echo "  curl http://<your-server>:8086/ping"
