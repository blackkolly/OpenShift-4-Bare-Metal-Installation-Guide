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
        listen-on port 53 { 127.0.0.1; 10.18.0.105; };
        listen-on-v6 port 53 { ::1; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { localhost; 10.18.0.0/24; };

        recursion yes;
        forward only;
        forwarders {
                10.18.0.3;
        };

        dnssec-enable yes;
        dnssec-validation yes;

        managed-keys-directory "/var/named/dynamic";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";

        include "/etc/crypto-policies/back-ends/bind.config";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";

// Forward zone
zone "ocp.txse.systems" IN {
    type master;
    file "ocp.txse.systems.db";
    allow-update { none; };
};

// Reverse zone
zone "0.18.10.in-addr.arpa" IN {
    type master;
    file "0.18.10.db";
    allow-update { none; };
};
EOF

# Create forward zone file
sudo tee /var/named/ocp.txse.systems.db > /dev/null << 'EOF'
$TTL 1W
@       IN      SOA     ns1.ocp.txse.systems. admin.ocp.txse.systems. (
                        2023011301      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.ocp.txse.systems.
        IN      MX 10   smtp.ocp.txse.systems.
        IN      A       10.18.0.105

ns1     IN      A       10.18.0.105
smtp    IN      A       10.18.0.105

; Services VM
services        IN      A       10.18.0.105

; OpenShift Cluster
bootstrap       IN      A       10.18.0.10
master-1        IN      A       10.18.0.11
master-2        IN      A       10.18.0.12
master-3        IN      A       10.18.0.13
worker-1        IN      A       10.18.0.21
worker-2        IN      A       10.18.0.22
worker-3        IN      A       10.18.0.23

; OpenShift Internal - Load balancer targets
api             IN      A       10.18.0.105
api-int         IN      A       10.18.0.105
*.apps          IN      A       10.18.0.105

; ETCD Cluster
etcd-0          IN      A       10.18.0.11
etcd-1          IN      A       10.18.0.12
etcd-2          IN      A       10.18.0.13

; ETCD SRV records
_etcd-server-ssl._tcp.ocp.txse.systems.    86400   IN    SRV     0   10   2380   etcd-0.ocp.txse.systems.
_etcd-server-ssl._tcp.ocp.txse.systems.    86400   IN    SRV     0   10   2380   etcd-1.ocp.txse.systems.
_etcd-server-ssl._tcp.ocp.txse.systems.    86400   IN    SRV     0   10   2380   etcd-2.ocp.txse.systems.
EOF

# Create reverse zone file
sudo tee /var/named/0.18.10.db > /dev/null << 'EOF'
$TTL 1W
@       IN      SOA     ns1.ocp.txse.systems. admin.ocp.txse.systems. (
                        2023011301      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.ocp.txse.systems.

; Services VM
105     IN      PTR     services.ocp.txse.systems.
105     IN      PTR     api.ocp.txse.systems.
105     IN      PTR     api-int.ocp.txse.systems.

; OpenShift Cluster
10      IN      PTR     bootstrap.ocp.txse.systems.
11      IN      PTR     master-1.ocp.txse.systems.
12      IN      PTR     master-2.ocp.txse.systems.
13      IN      PTR     master-3.ocp.txse.systems.
21      IN      PTR     worker-1.ocp.txse.systems.
22      IN      PTR     worker-2.ocp.txse.systems.
23      IN      PTR     worker-3.ocp.txse.systems.

; ETCD Cluster
11      IN      PTR     etcd-0.ocp.txse.systems.
12      IN      PTR     etcd-1.ocp.txse.systems.
13      IN      PTR     etcd-2.ocp.txse.systems.
EOF

# Set proper permissions
sudo chown named:named /var/named/ocp.txse.systems.db
sudo chown named:named /var/named/0.18.10.db

# Configure firewall
sudo firewall-cmd --add-port=53/udp --permanent
sudo firewall-cmd --add-port=53/tcp --permanent
sudo firewall-cmd --reload

# Enable and start named service
sudo systemctl enable named
sudo systemctl restart named

# Configure network to use local DNS
sudo nmcli con mod "System mgmt0" ipv4.dns "127.0.0.1"
sudo systemctl restart NetworkManager

# Test DNS resolution
dig master-1.ocp.txse.systems @localhost
dig -x 10.18.0.11 @localhost
dig _etcd-server-ssl._tcp.ocp.txse.systems SRV @localhost

echo "==> DNS setup completed successfully"
