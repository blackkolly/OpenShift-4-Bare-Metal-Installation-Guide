#!/bin/bash

# This script configures the DNS server on the services VM

set -e

echo "==> Setting up DNS server (BIND)"

# Install bind if not already installed
if ! rpm -q bind &>/dev/null; then
    sudo dnf install -y bind bind-utils
fi

# Create named.conf
sudo tee /etc/named.conf > /dev/null << 'EOF'
options {
        listen-on port 53 { 127.0.0.1; 192.168.22.1; };
        listen-on-v6 port
