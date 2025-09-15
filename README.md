# OpenShift 4 Installation on VMs

This repository provides a comprehensive guide for deploying Red Hat OpenShift 4 on existing VMs in the data center environment. This implementation follows the User Provisioned Infrastructure (UPI) method with 3 control plane nodes and 3 worker nodes.

## Table of Contents

- [VM Requirements](#vm-requirements)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
  - [1. Configure VM Networking](#1-configure-vm-networking)
  - [2. Set Up Services VM](#2-set-up-services-vm)
  - [3. Generate Installation Files](#3-generate-installation-files)
  - [4. Deploy OpenShift Nodes](#4-deploy-openshift-nodes)
  - [5. Monitor Installation](#5-monitor-installation)
  - [6. Post-Installation Tasks](#6-post-installation-tasks)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## VM Requirements

You will need to allocate **8 virtual machines** from your txse.systems data center across your three 32GB servers:

| VM Role    | VM Name    | IP Address   | Function                        | Server    |
|------------|------------|--------------|----------------------------------|-----------|
| Services   | services   | 10.18.0.105  | DNS, HAProxy, HTTP, NFS          | Server 1  |
| Bootstrap  | bootstrap  | 10.18.0.10   | Temporary bootstrap node         | Server 3  |
| Master 1   | master-1   | 10.18.0.11   | Control plane node               | Server 2  |
| Master 2   | master-2   | 10.18.0.12   | Control plane node               | Server 2  |
| Master 3   | master-3   | 10.18.0.13   | Control plane node               | Server 2  |
| Worker 1   | worker-1   | 10.18.0.21   | Compute node                     | Server 3  |
| Worker 2   | worker-2   | 10.18.0.22   | Compute node                     | Server 3  |
| Worker 3   | worker-3   | 10.18.0.23   | Compute node                     | Server 3  |

**Note:** These IP addresses use your existing 10.18.0.0/24 network. We're using the existing server at 10.18.0.105 as the services VM.

### Minimum VM Specifications

| VM Type    | vCPU | RAM  | Storage | Operating System              |
|------------|------|------|---------|-------------------------------|
| Services   | 2    | 4GB  | 50GB    | Rocky Linux 8 or RHEL 8       |
| Bootstrap  | 4    | 8GB  | 120GB   | RHCOS (Installed during setup)|
| Master     | 4    | 6GB  | 120GB   | RHCOS (Installed during setup)|
| Worker     | 8    | 8GB  | 120GB   | RHCOS (Installed during setup)|

Based on your three 32GB RAM servers, we've adjusted the RAM allocation to ensure everything fits.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                     Data Center Network (10.18.0.0/24)                        │
│                                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  services   │  │  bootstrap  │  │  master-1   │  │  master-2   │          │
│  │     VM      │  │     VM      │  │     VM      │  │     VM      │          │
│  │ 10.18.0.105 │  │ 10.18.0.10  │  │ 10.18.0.11  │  │ 10.18.0.12  │          │
│  │ - DNS       │  │ (Temporary) │  │ Control     │  │ Control     │          │
│  │ - HAProxy   │  │ Bootstrap   │  │ Plane       │  │ Plane       │          │
│  │ - HTTP      │  │ Node        │  │ Node        │  │ Node        │          │
│  │ - NFS       │  │             │  │             │  │             │          │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘          │
│    Server 1         Server 3         Server 2         Server 2               │
│                                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  master-3   │  │  worker-1   │  │  worker-2   │  │  worker-3   │          │
│  │     VM      │  │     VM      │  │     VM      │  │     VM      │          │
│  │ 10.18.0.13  │  │ 10.18.0.21  │  │ 10.18.0.22  │  │ 10.18.0.23  │          │
│  │ Control     │  │ Compute     │  │ Compute     │  │ Compute     │          │
│  │ Plane       │  │ Node        │  │ Node        │  │ Node        │          │
│  │ Node        │  │             │  │             │  │             │          │
│  │             │  │             │  │             │  │             │          │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘          │
│    Server 2         Server 3         Server 3         Server 3               │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Software Requirements

- Rocky Linux 8.5 or later / RHEL 8 on the services VM
- Red Hat account to download:
  - OpenShift installation files
  - Pull secret
  - Red Hat CoreOS (RHCOS) images

### Network Requirements

- All VMs must be on the same network (10.18.0.0/24)
- All VMs must be able to communicate with each other
- Required ports must be open between VMs (see firewall configuration in setup scripts)

## Installation Steps

### 1. Configure VM Networking

#### Configure Static IP Addresses

For each VM, set a static IP address according to the table above:

```bash
# VM: services, master-1, master-2, master-3, worker-1, worker-2, worker-3
# Example for a VM:

# Find the network interface name
sudo nmcli con show

# Configure static IP (adjust IP for each VM)
sudo nmcli con mod "System mgmt0" \
  ipv4.addresses 10.18.0.11/24 \
  ipv4.gateway 10.18.0.1 \
  ipv4.method manual

# Apply changes
sudo nmcli con up "System mgmt0"

# Verify configuration
ip addr show
```

#### Verify Network Connectivity

```bash
# Test connectivity between VMs
ping -c 3 10.18.0.105
ping -c 3 10.18.0.11
```

### 2. Set Up Services VM

All of the following steps should be performed on the services VM (10.18.0.105).

#### Install Required Packages

```bash
# VM: services (10.18.0.105)
sudo dnf install -y bind bind-utils dhcp-server haproxy httpd wget git \
  bash-completion vim tmux tar jq podman httpd-tools chrony net-tools nfs-utils
```

#### Configure DNS Server

```bash
# VM: services (10.18.0.105)
# Create named.conf file
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
```

#### Configure HAProxy Load Balancer

```bash
# VM: services (10.18.0.105)
# Configure HAProxy
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
```

#### Configure Web Server

```bash
# VM: services (10.18.0.105)
# Configure Apache to listen on port 8080 to avoid conflict with HAProxy
sudo sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf

# Create directory structure
sudo mkdir -p /var/www/html/ocp4/{ignition,images}

# Configure firewall
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload

# Set permissions
sudo chown -R apache:apache /var/www/html/ocp4
sudo chmod -R 755 /var/www/html/ocp4

# Enable and start Apache service
sudo systemctl enable httpd
sudo systemctl restart httpd

# Create a test file
echo "OpenShift 4 Installation Server" | sudo tee /var/www/html/ocp4/index.html > /dev/null
sudo chown apache:apache /var/www/html/ocp4/index.html

# Test the web server
curl http://localhost:8080/ocp4/
```

#### Configure NFS Server for Registry

```bash
# VM: services (10.18.0.105)
# Create registry directory
sudo mkdir -p /exports/registry

# Set permissions
sudo chown -R nobody:nobody /exports/registry
sudo chmod -R 777 /exports/registry

# Configure exports
sudo tee /etc/exports > /dev/null << EOF
/exports/registry *(rw,sync,root_squash,no_wdelay,no_subtree_check)
EOF

# Configure firewall
sudo firewall-cmd --add-service=nfs --permanent
sudo firewall-cmd --add-service=mountd --permanent
sudo firewall-cmd --add-service=rpc-bind --permanent
sudo firewall-cmd --reload

# Enable and start NFS services
sudo systemctl enable nfs-server
sudo systemctl restart nfs-server
sudo exportfs -rv
```

### 3. Generate Installation Files

#### Download OpenShift Installer and Client

```bash
# VM: services (10.18.0.105)
# Create project directory
mkdir -p ~/ocp-install

# Download OpenShift client and installer
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz

# Extract the files
tar -xzf openshift-client-linux.tar.gz -C /tmp
tar -xzf openshift-install-linux.tar.gz -C /tmp

# Move binaries to a directory in PATH
sudo mv /tmp/oc /tmp/kubectl /usr/local/bin/
sudo mv /tmp/openshift-install /usr/local/bin/

# Download RHCOS images
OCP_VERSION=$(openshift-install version | grep -oP 'release image.*CoreOS: \K[0-9.]+')
BASEURL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${OCP_VERSION:0:4}/${OCP_VERSION}"

wget -P /var/www/html/ocp4/images/ ${BASEURL}/rhcos-${OCP_VERSION}-x86_64-live.x86_64.iso
wget -P /var/www/html/ocp4/images/ ${BASEURL}/rhcos-${OCP_VERSION}-x86_64-metal.x86_64.raw.gz

# Set proper permissions
sudo chown -R apache:apache /var/www/html/ocp4/images/
```

#### Create Installation Configuration

```bash
# VM: services (10.18.0.105)
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa

# Create install-config.yaml
cat > ~/ocp-install/install-config.yaml << EOF
apiVersion: v1
baseDomain: txse.systems
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: ocp
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '$(cat ~/pull-secret.txt)'
sshKey: '$(cat ~/.ssh/id_rsa.pub)'
EOF

# Back up the install-config.yaml
cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml.bak
```

#### Generate Ignition Files

```bash
# VM: services (10.18.0.105)
# Generate the Kubernetes manifests
openshift-install create manifests --dir=~/ocp-install

# Optional: Make control plane nodes non-schedulable (recommended for production)
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g' ~/ocp-install/manifests/cluster-scheduler-02-config.yml

# Generate the Ignition configs
openshift-install create ignition-configs --dir=~/ocp-install

# Copy ignition files to web server directory
sudo cp ~/ocp-install/*.ign /var/www/html/ocp4/ignition/
sudo chown apache:apache /var/www/html/ocp4/ignition/*.ign
sudo chmod 644 /var/www/html/ocp4/ignition/*.ign

# Verify files are accessible
curl -I http://localhost:8080/ocp4/ignition/bootstrap.ign
```

### 4. Deploy OpenShift Nodes

#### Prepare Bootstrap and OpenShift Nodes

For each VM (bootstrap, master-1/2/3, worker-1/2/3), you'll need to boot from the RHCOS ISO and configure it to install using the appropriate ignition file.

For the bootstrap node:

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following kernel parameters:

```
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/bootstrap.ign ip=10.18.0.10::10.18.0.1:255.255.255.0:bootstrap.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105
```

For each master node (adjust IP address and hostname for each node):

```
# Master-1 (10.18.0.11)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.11::10.18.0.1:255.255.255.0:master-1.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

# Master-2 (10.18.0.12)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.12::10.18.0.1:255.255.255.0:master-2.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

# Master-3 (10.18.0.13)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.13::10.18.0.1:255.255.255.0:master-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105
```

For each worker node (adjust IP address and hostname for each node):

```
# Worker-1 (10.18.0.21)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.21::10.18.0.1:255.255.255.0:worker-1.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

# Worker-2 (10.18.0.22)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.22::10.18.0.1:255.255.255.0:worker-2.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

# Worker-3 (10.18.0.23)
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-<version>-metal.x86_64.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.23::10.18.0.1:255.255.255.0:worker-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105
```

**Note:** Replace `<version>` with the actual RHCOS version you downloaded.

### 5. Monitor Installation

#### Monitor Bootstrap Process

```bash
# VM: services (10.18.0.105)
# Watch the bootstrap progress
openshift-install --dir=~/ocp-install wait-for bootstrap-complete --log-level=info
```

Once bootstrap is complete, you can remove the bootstrap node from the load balancer:

```bash
# VM: services (10.18.0.105)
# Edit HAProxy configuration to remove bootstrap entries
sudo sed -i '/server bootstrap /d' /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
```

#### Monitor Cluster Operator Deployment

```bash
# VM: services (10.18.0.105)
# Set the KUBECONFIG environment variable
export KUBECONFIG=~/ocp-install/auth/kubeconfig

# Watch the cluster operators come online
watch -n5 oc get co
```

#### Approve Certificate Signing Requests (CSRs) for Worker Nodes

```bash
# VM: services (10.18.0.105)
# Check for pending CSRs
oc get csr

# Approve all pending CSRs
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve

# Continue approving CSRs until all nodes are ready
watch -n5 oc get nodes
```

#### Wait for Installation to Complete

```bash
# VM: services (10.18.0.105)
openshift-install --dir=~/ocp-install wait-for install-complete
```

### 6. Post-Installation Tasks

#### Configure Storage for the Image Registry

```bash
# VM: services (10.18.0.105)
# Create the registry persistent volume
cat << EOF | oc create -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: registry-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /exports/registry
    server: 10.18.0.105
EOF

# VM: services (10.18.0.105)
# Configure the image registry operator
oc patch configs.imageregistry.operator.openshift.io cluster --type=merge --patch '{"spec":{"managementState":"Managed"}}'
oc patch configs.imageregistry.operator.openshift.io cluster --type=merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'

# Wait for the PVC to be created
sleep 10

# Verify that the PVC is bound
oc get pvc -n openshift-image-registry

# Display registry pod status
oc get pods -n openshift-image-registry
```

#### Create Admin User

```bash
# VM: services (10.18.0.105)
# Generate htpasswd entry
ADMIN_USER="admin"
ADMIN_PASSWORD="password"  # Change this to a secure password
HTPASSWD_DATA=$(htpasswd -nb -B $ADMIN_USER $ADMIN_PASSWORD)

# Create OAuth configuration with HTPasswd identity provider
cat << EOF | oc create -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: htpasswd-secret
  namespace: openshift-config
type: Opaque
data:
  htpasswd: $(echo -n "$HTPASSWD_DATA" | base64 -w0)
EOF

# Assign cluster-admin role to the user
oc adm policy add-cluster-role-to-user cluster-admin $ADMIN_USER
```

#### Access the OpenShift Web Console

The console URL will be displayed in the output of the `wait-for install-complete` command, typically in the format:

```
https://console-openshift-console.apps.ocp.txse.systems
```

You can log in with the admin user you created.

## Troubleshooting

### Common Issues and Solutions

#### 1. DNS Resolution Issues

**Symptoms:**
- Nodes cannot resolve each other's hostnames
- API endpoint cannot be reached
- Bootstrap process fails with DNS-related errors

**Solutions:**
- Verify DNS service is running on the services VM: `sudo systemctl status named`
- Check DNS configuration: `sudo named-checkconf /etc/named.conf`
- Test DNS resolution: `dig master-1.ocp.txse.systems @10.18.0.105`
- Check DNS server logs: `sudo journalctl -u named`
- Make sure all VMs are configured to use the services VM (10.18.0.105) as their DNS server

#### 2. Load Balancer Issues

**Symptoms:**
- OpenShift API is not accessible
- Installation fails with connection timeout errors
- Services cannot be accessed through the ingress

**Solutions:**
- Verify HAProxy is running: `sudo systemctl status haproxy`
- Check HAProxy configuration: `sudo haproxy -c -f /etc/haproxy/haproxy.cfg`
- Examine HAProxy statistics: `http://10.18.0.105:9000/`
- Test connections to backend services: `curl -k https://api.ocp.txse.systems:6443/version`
- Check SELinux settings: `sudo setsebool -P haproxy_connect_any 1`

#### 3. Network Interface Issues

**Symptoms:**
- Nodes fail to boot properly
- Network connectivity issues between nodes
- DHCP or static IP assignment failures

**Solutions:**
- Verify that you're using the correct network interface name (`mgmt0`) in all boot parameters
- Check network connectivity between nodes: `ping 10.18.0.11` from other nodes
- Verify gateway configuration: `ip route show`
- Test DNS resolution: `dig master-1.ocp.txse.systems`

#### 4. Resource Allocation Issues

**Symptoms:**
- VMs fail to start due to insufficient resources
- Performance degradation during installation
- Nodes become unresponsive

**Solutions:**
- Verify that each server has sufficient resources for the VMs assigned to it
- Consider reducing the memory allocation for VMs if necessary
- Ensure that the total resources allocated to VMs don't exceed the physical server's capabilities
- Monitor resource usage during installation: `top`, `free -m`, `df -h`

#### 5. CSR Approval Issues

**Symptoms:**
- Worker nodes not joining the cluster
- CSRs stuck in pending state
- Node status remains NotReady

**Solutions:**
- Check for pending CSRs: `oc get csr`
- Approve all pending CSRs: `oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve`
- Verify worker node networking
- Check worker node logs: `ssh core@worker-1.ocp.txse.systems journalctl -f -u kubelet`

### Collecting Diagnostic Information

For comprehensive diagnostic information, run:

```bash
# VM: services (10.18.0.105)
# Create a diagnostics directory
DIAG_DIR=~/ocp-diagnostics-$(date +%Y%m%d-%H%M%S)
mkdir -p $DIAG_DIR

# Set KUBECONFIG if not already set
export KUBECONFIG=~/ocp-install/auth/kubeconfig

# Collect node information
echo "Collecting node information..."
oc get nodes -o wide > $DIAG_DIR/nodes.txt
oc get nodes -o yaml > $DIAG_DIR/nodes-yaml.txt

# Collect pod information
echo "Collecting pod information..."
oc get pods --all-namespaces -o wide > $DIAG_DIR/pods.txt
oc get pods --all-namespaces | grep -v Running > $DIAG_DIR/non-running-pods.txt

# Collect cluster operator status
echo "Collecting cluster operator status..."
oc get co > $DIAG_DIR/cluster-operators.txt
oc get co -o yaml > $DIAG_DIR/cluster-operators-yaml.txt

# Collect events
echo "Collecting events..."
oc get events --all-namespaces > $DIAG_DIR/events.txt

# Collect logs from problematic pods
echo "Collecting logs from key components..."
mkdir -p $DIAG_DIR/logs
for ns in openshift-etcd openshift-apiserver openshift-authentication openshift-ingress; do
    for pod in $(oc get pods -n $ns -o name); do
        pod_name=$(echo $pod | cut -d/ -f2)
        oc logs $pod -n $ns > $DIAG_DIR/logs/$ns-$pod_name.log 2>/dev/null || true
    done
done

# Compress the diagnostics directory
tar -czf ocp-diagnostics.tar.gz $DIAG_DIR
echo "Diagnostics collected in ocp-diagnostics.tar.gz"
```

You can also use the OpenShift must-gather tool for deeper diagnostics:

```bash
oc adm must-gather --dest-dir=$DIAG_DIR/must-gather
```

## Server-Specific Configuration

### Server 1 (10.18.0.105) - Services VM

This server hosts the services VM with DNS, DHCP, HAProxy, web server, and NFS. It should have:
- 4GB RAM allocated for the services VM
- Remaining resources available for the host system

### Server 2 - Control Plane Nodes

This server hosts all three master/control plane nodes:
- master-1 (10.18.0.11) - 6GB RAM
- master-2 (10.18.0.12) - 6GB RAM 
- master-3 (10.18.0.13) - 6GB RAM
- Total: 18GB RAM (with 14GB remaining for the host system)

### Server 3 - Bootstrap and Worker Nodes

This server hosts the bootstrap node (temporary) and all worker nodes:
- bootstrap (10.18.0.10) - 8GB RAM (can be removed after installation)
- worker-1 (10.18.0.21) - 8GB RAM
- worker-2 (10.18.0.22) - 8GB RAM
- worker-3 (10.18.0.23) - 8GB RAM
- Total: 24GB RAM for VMs (with 8GB remaining for the host system)

**Note:** Once the bootstrap node is removed, there will be 16GB RAM allocated for worker nodes.

## Complete Installation Script

Here's a complete script that runs all the installation steps in sequence:

```bash
#!/bin/bash

# OpenShift 4 installation script for txse.systems
# Run this on the services VM (10.18.0.105)

set -e

echo "===== OpenShift 4 Installation on txse.systems ====="
echo "This script will install OpenShift 4 on your data center VMs"
echo "Make sure all VMs are properly configured before proceeding"
echo

# Ask for confirmation
read -p "Are you ready to proceed? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Installation aborted"
    exit 1
fi

# Create installation directory
mkdir -p ~/ocp-install

# Step 1: Configure DNS
echo
echo "===== Step 1: Setting up DNS server ====="
# DNS setup commands go here (see DNS section above)

# Step 2: Configure HAProxy
echo
echo "===== Step 2: Setting up HAProxy load balancer ====="
# HAProxy setup commands go here (see HAProxy section above)

# Step 3: Configure Web Server
echo
echo "===== Step 3: Setting up Web Server ====="
# Web server setup commands go here (see Web Server section above)

# Step 4: Configure NFS Server
echo
echo "===== Step 4: Setting up NFS Server ====="
# NFS setup commands go here (see NFS section above)

# Step 5: Download OpenShift Files
echo
echo "===== Step 5: Downloading OpenShift Files ====="
# Download commands go here (see Download section above)

# Step 6: Generate Ignition Files
echo
echo "===== Step 6: Generating Ignition Files ====="
# Ignition generation commands go here (see Ignition section above)

# Step 7: Boot VMs
echo
echo "===== Step 7: Ready to Boot VMs ====="
echo "You must now boot each VM with the RHCOS ISO and appropriate boot parameters"
echo "See the README.md section on booting nodes for detailed instructions"
echo
echo "Boot the bootstrap node first, followed by the master nodes."
echo

read -p "Have you booted the bootstrap and master nodes? (y/n): " booted
if [ "$booted" != "y" ]; then
    echo "Please boot the nodes and then continue"
    exit 1
fi

# Step 8: Monitor Bootstrap Process
echo
echo "===== Step 8: Monitoring Bootstrap Process ====="
openshift-install --dir=~/ocp-install wait-for bootstrap-complete --log-level=info

# Step 9: Remove Bootstrap Node
echo
echo "===== Step 9: Removing Bootstrap Node ====="
sudo sed -i '/server bootstrap /d' /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy

# Step 10: Boot Worker Nodes
echo
echo "===== Step 10: Booting Worker Nodes ====="
echo "Please boot your worker nodes now if you haven't already"
echo

read -p "Have you booted the worker nodes? (y/n): " worker_booted
if [ "$worker_booted" != "y" ]; then
    echo "Please boot the worker nodes and then continue"
    exit 1
fi

# Step 11: Approve CSRs
echo
echo "===== Step 11: Approving Worker Node CSRs ====="
export KUBECONFIG=~/ocp-install/auth/kubeconfig

# Loop to approve CSRs
for i in {1..10}; do
    echo "Checking for pending CSRs (attempt $i of 10)..."
    PENDING_CSRS=$(oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
    
    if [ -n "$PENDING_CSRS" ]; then
        echo "Approving CSRs..."
        echo "$PENDING_CSRS" | xargs oc adm certificate approve
    else
        echo "No pending CSRs found."
    fi
    
    echo "Waiting 30 seconds before next check..."
    sleep 30
done

# Step 12: Wait for Installation to Complete
echo
echo "===== Step 12: Waiting for Installation to Complete ====="
openshift-install --dir=~/ocp-install wait-for install-complete

# Step 13: Configure Registry Storage
echo
echo "===== Step 13: Configuring Registry Storage ====="
# Registry configuration commands go here (see Registry section above)

# Step 14: Create Admin User
echo
echo "===== Step 14: Creating Admin User ====="
# Admin user creation commands go here (see Admin User section above)

echo
echo "===== Installation Complete ====="
echo "You can now access the OpenShift console at:"
echo "https://console-openshift-console.apps.ocp.txse.systems"
echo
echo "Admin credentials:"
echo "Username: admin"
echo "Password: password (or the password you specified)"
echo
echo "Enjoy your new OpenShift cluster!"
```

## References

- [Official OpenShift 4 Documentation](https://docs.openshift.com/container-platform/4.11/installing/installing_bare_metal/installing-bare-metal.html)
- [Red Hat CoreOS Documentation](https://docs.openshift.com/container-platform/4.11/architecture/architecture-rhcos.html)
- [KVM/libvirt Documentation](https://libvirt.org/docs.html)
- [Red Hat OpenShift Blog](https://www.redhat.com/blog/topic/openshift)
