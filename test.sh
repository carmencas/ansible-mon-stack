#!/bin/bash

echo "=== Testing the Monitoring Stack ==="

# Retrieve the monitor server IP
MONITOR_IP=$(grep -A1 '\[prometheus\]' inventory/hosts.ini | tail -1 | cut -d'=' -f2)

echo "Monitor server: $MONITOR_IP"
echo

# Test Prometheus
echo "🔍 Testing Prometheus..."
if curl -s -f "http://$MONITOR_IP:9090/-/healthy" > /dev/null; then
    echo "✅ Prometheus OK"
    
    # Count active targets
    TARGETS=$(curl -s "http://$MONITOR_IP:9090/api/v1/targets" | jq '.data.activeTargets | length')
    echo "   📊 Active targets: $TARGETS"
else
    echo "❌ Prometheus FAILED"
fi

# Test InfluxDB
echo "🔍 Testing InfluxDB..."
if curl -s -f "http://$MONITOR_IP:8086/ping" > /dev/null; then
    echo "✅ InfluxDB OK"
else
    echo "❌ InfluxDB FAILED"
fi

# Test Node Exporters
echo "🔍 Testing Node Exporters..."
for host in $(grep ansible_host inventory/hosts.ini | cut -d'=' -f2); do
    if curl -s -f "http://$host:9100/metrics" > /dev/null; then
        echo "✅ Node Exporter $host OK"
    else
        echo "❌ Node Exporter $host FAILED"
    fi
done

echo
echo "=== Testing Complete ==="
