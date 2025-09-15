#!/bin/bash

# This script configures the HAProxy load balancer on the services VM

set -e

echo "==> Setting up HAProxy load balancer"

# Install HAProxy if not already installed
if ! rpm -q haproxy &>/dev/null; then
    sudo dnf install -y haproxy
fi

# Create HAProxy configuration
sudo tee /etc/haproxy/haproxy.cfg > /dev/null << 'EOF'
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

# Stats Page
listen stats
    bind :9000
    mode http
    stats enable
    stats uri /
    stats refresh 30s
    stats show-legends
    stats show-node

# OpenShift API (Kubernetes API)
frontend openshift-api-server
    bind *:6443
    default_backend openshift-api-server
    mode tcp
    option tcplog

backend openshift-api-server
    balance source
    mode tcp
    server bootstrap 10.18.0.10:6443 check
    server master-1 10.18.0.11:6443 check
    server master-2 10.18.0.12:6443 check
    server master-3 10.18.0.13:6443 check

# OpenShift Machine Config Server
frontend machine-config-server
    bind *:22623
    default_backend machine-config-server
    mode tcp
    option tcplog

backend machine-config-server
    balance source
    mode tcp
    server bootstrap 10.18.0.10:22623 check
    server master-1 10.18.0.11:22623 check
    server master-2 10.18.0.12:22623 check
    server master-3 10.18.0.13:22623 check

# OpenShift Ingress HTTPS
frontend openshift-ingress-https
    bind *:443
    default_backend openshift-ingress-https
    mode tcp
    option tcplog

backend openshift-ingress-https
    balance source
    mode tcp
    server worker-1 10.18.0.21:443 check
    server worker-2 10.18.0.22:443 check
    server worker-3 10.18.0.23:443 check

# OpenShift Ingress HTTP
frontend openshift-ingress-http
    bind *:80
    default_backend openshift-ingress-http
    mode tcp
    option tcplog

backend openshift-ingress-http
    balance source
    mode tcp
    server worker-1 10.18.0.21:80 check
    server worker-2 10.18.0.22:80 check
    server worker-3 10.18.0.23:80 check
EOF

# Configure firewall
sudo firewall-cmd --add-port=6443/tcp --permanent
sudo firewall-cmd --add-port=22623/tcp --permanent
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --add-port=9000/tcp --permanent
sudo firewall-cmd --reload

# Configure SELinux
sudo setsebool -P haproxy_connect_any 1

# Enable and start HAProxy service
sudo systemctl enable haproxy
sudo systemctl restart haproxy

echo "==> HAProxy setup completed successfully"
echo "HAProxy stats available at: http://10.18.0.105:9000/"
