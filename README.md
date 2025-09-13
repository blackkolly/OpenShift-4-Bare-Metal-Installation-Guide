# OpenShift 4 Bare Metal Installation Guide

This repository provides a complete implementation guide for installing Red Hat OpenShift 4 on bare metal using virtual machines with User Provisioned Infrastructure (UPI). The configuration includes 3 master nodes and 3 worker nodes.

## Architecture

![OpenShift 4 Architecture](images/ocp4-architecture.png)

### Components

- **1x Services VM** - Provides supporting infrastructure:
  - DNS (BIND)
  - DHCP
  - HAProxy (Load Balancer)
  - Web Server (to host ignition files)
  - NFS (for Registry storage)

- **1x Bootstrap Node** (temporary)
  - Initiates the OpenShift cluster deployment
  - Removed after installation completes

- **3x Control Plane Nodes**
  - Run the Kubernetes/OpenShift control plane components
  - Host etcd database in a highly available configuration

- **3x Worker Nodes**
  - Run application workloads
  - Host OpenShift router/ingress components

## Prerequisites

### Hardware Requirements

- A hypervisor host (ESXi, KVM, or other virtualization platform)
- Minimum 64GB RAM
- Minimum 8 CPU cores
- At least 500GB storage space

### Software Requirements

- Red Hat account with OpenShift subscription
- CentOS 8/RHEL 8 (for services VM)
- Red Hat CoreOS (RHCOS) ISO and RAW images
- OpenShift installation files and pull secret

## Directory Structure

```
├── configs/               # Configuration files for infrastructure services
│   ├── dhcpd.conf         # DHCP server configuration
│   ├── haproxy.cfg        # HAProxy load balancer configuration
│   ├── named.conf         # BIND DNS server configuration
│   ├── dns/               # DNS zone files
│   └── registry-pv.yaml   # Registry persistent volume configuration
├── scripts/               # Helper scripts for installation process
│   ├── setup-services.sh  # Sets up all services on the services VM
│   ├── create-iso.sh      # Creates customized boot ISOs for nodes
│   ├── setup-registry.sh  # Configures storage for the registry
│   └── approve-csrs.sh    # Approves certificate signing requests for worker nodes
├── docs/                  # Additional documentation
│   └── troubleshooting.md # Troubleshooting guide
└── images/                # Architecture diagrams and screenshots
```

## Installation Steps

### Phase 1: Prepare the Environment

1. [Download Required Software](#download-required-software)
2. [Create Virtual Machines](#create-virtual-machines)
3. [Configure the Services VM](#configure-the-services-vm)

### Phase 2: Deploy OpenShift

4. [Generate and Host Installation Files](#generate-and-host-installation-files)
5. [Deploy the Bootstrap and Master Nodes](#deploy-the-bootstrap-and-master-nodes)
6. [Monitor the Bootstrap Process](#monitor-the-bootstrap-process)
7. [Deploy Worker Nodes](#deploy-worker-nodes)

### Phase 3: Complete the Installation

8. [Remove the Bootstrap Node](#remove-the-bootstrap-node)
9. [Configure Storage for the Registry](#configure-storage-for-the-registry)
10. [Create the First Admin User](#create-the-first-admin-user)
11. [Access the OpenShift Console](#access-the-openshift-console)

## Detailed Installation Guide

### Download Required Software

1. **Download CentOS 8 (or RHEL 8) for the Services VM**
   ```bash
   wget https://mirror.stream.centos.org/8-stream/x86_64/images/CentOS-Stream-8-x86_64-latest.iso
   ```

2. **Log in to the Red Hat OpenShift Cluster Manager**
   - Go to https://cloud.redhat.com/openshift
   - Navigate to Create Cluster > Red Hat OpenShift Container Platform > Run on Bare Metal

3. **Download the following files**:
   - OpenShift Installer for Linux
   - Pull secret (save as `pull-secret.txt`)
   - Command Line Interface (CLI) tools
   - Red Hat CoreOS (RHCOS) ISO and RAW images
   ```bash
   # Example commands to download OpenShift files
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
   wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-live.x86_64.iso
   wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-metal.x86_64.raw.gz
   ```

### Create Virtual Machines

Create the following VMs in your hypervisor environment:

1. **Services VM**
   - 4 vCPUs
   - 8 GB RAM
   - 120 GB disk
   - 2 network interfaces:
     - NIC1: Connected to your external network
     - NIC2: Connected to the internal OpenShift network

2. **Bootstrap Node** (temporary)
   - 4 vCPUs
   - 16 GB RAM
   - 120 GB disk
   - Connected to the internal OpenShift network

3. **Control Plane Nodes (3)**
   - 4 vCPUs each
   - 16 GB RAM each
   - 120 GB disk each
   - Connected to the internal OpenShift network

4. **Worker Nodes (3)**
   - 8 vCPUs each (minimum 4)
   - 16 GB RAM each (minimum 8)
   - 120 GB disk each
   - Connected to the internal OpenShift network

5. **Record MAC Addresses**
   - Boot each VM to obtain MAC addresses, then shut them down
   - Note the MAC address of each VM for DHCP configuration

### Configure the Services VM

1. **Install CentOS/RHEL 8**
   - Install with minimal configuration
   - Configure only the external NIC during installation
   - Set a static IP for the internal NIC after installation

2. **Copy Installation Files**
   ```bash
   scp openshift-install-linux.tar.gz openshift-client-linux.tar.gz rhcos-live.x86_64.iso rhcos-metal.x86_64.raw.gz pull-secret.txt root@<services-vm-ip>:~
   ```

3. **Extract the OpenShift Installer and CLI Tools**
   ```bash
   ssh root@<services-vm-ip>
   tar -xzf openshift-install-linux.tar.gz
   tar -xzf openshift-client-linux.tar.gz
   mv oc kubectl /usr/local/bin/
   ```

4. **Configure Internal Network Interface**
   ```bash
   # Using nmtui or by editing configuration files
   nmtui-edit ens224  # Adjust interface name as needed
   
   # Set the following:
   # IP address: 192.168.22.1
   # Netmask: 255.255.255.0
   # Never use this network for default route
   
   # Apply changes
   nmcli connection down ens224
   nmcli connection up ens224
   ```

5. **Configure Firewall Zones and Masquerading**
   ```bash
   # Create internal and external zones
   nmcli connection modify ens192 connection.zone external
   nmcli connection modify ens224 connection.zone internal
   
   # Configure masquerading
   firewall-cmd --zone=external --add-masquerade --permanent
   firewall-cmd --zone=internal --add-masquerade --permanent
   firewall-cmd --reload
   ```

6. **Install and Configure DNS Server (BIND)**
   ```bash
   # Install BIND
   dnf install -y bind bind-utils
   
   # Copy configuration files
   cp ./configs/named.conf /etc/named.conf
   mkdir -p /var/named
   cp ./configs/dns/ocp.lan.db /var/named/
   cp ./configs/dns/22.168.192.db /var/named/
   
   # Set proper permissions
   chown -R named:named /var/named
   
   # Configure firewall
   firewall-cmd --add-port=53/udp --zone=internal --permanent
   firewall-cmd --add-port=53/tcp --zone=internal --permanent
   firewall-cmd --reload
   
   # Enable and start the service
   systemctl enable --now named
   ```

7. **Install and Configure DHCP Server**
   ```bash
   # Install DHCP server
   dnf install -y dhcp-server
   
   # Copy configuration
   cp ./configs/dhcpd.conf /etc/dhcp/dhcpd.conf
   
   # Configure firewall
   firewall-cmd --add-service=dhcp --zone=internal --permanent
   firewall-cmd --reload
   
   # Enable and start the service
   systemctl enable --now dhcpd
   ```

8. **Install and Configure Apache Web Server**
   ```bash
   # Install Apache
   dnf install -y httpd
   
   # Configure to listen on port 8080
   sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
   
   # Configure firewall
   firewall-cmd --add-port=8080/tcp --zone=internal --permanent
   firewall-cmd --reload
   
   # Create directory for ignition files
   mkdir -p /var/www/html/ocp4
   
   # Enable and start the service
   systemctl enable --now httpd
   ```

9. **Install and Configure HAProxy**
   ```bash
   # Install HAProxy
   dnf install -y haproxy
   
   # Copy configuration
   cp ./configs/haproxy.cfg /etc/haproxy/haproxy.cfg
   
   # Configure firewall
   firewall-cmd --add-port=6443/tcp --zone=internal --permanent
   firewall-cmd --add-port=6443/tcp --zone=external --permanent
   firewall-cmd --add-port=22623/tcp --zone=internal --permanent
   firewall-cmd --add-service=http --zone=internal --permanent
   firewall-cmd --add-service=http --zone=external --permanent
   firewall-cmd --add-service=https --zone=internal --permanent
   firewall-cmd --add-service=https --zone=external --permanent
   firewall-cmd --add-port=9000/tcp --zone=external --permanent
   firewall-cmd --reload
   
   # Enable and start the service
   setsebool -P haproxy_connect_any 1
   systemctl enable --now haproxy
   ```

10. **Configure NFS for Registry Storage**
    ```bash
    # Install NFS
    dnf install -y nfs-utils
    
    # Create export directory
    mkdir -p /shares/registry
    chown -R nobody:nobody /shares/registry
    chmod -R 777 /shares/registry
    
    # Configure exports
    echo "/shares/registry  192.168.22.0/24(rw,sync,root_squash,no_subtree_check,no_wdelay)" > /etc/exports
    exportfs -rv
    
    # Configure firewall
    firewall-cmd --zone=internal --add-service mountd --permanent
    firewall-cmd --zone=internal --add-service rpc-bind --permanent
    firewall-cmd --zone=internal --add-service nfs --permanent
    firewall-cmd --reload
    
    # Enable and start services
    systemctl enable --now nfs-server rpcbind
    ```

### Generate and Host Installation Files

1. **Generate SSH Key Pair**
   ```bash
   ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
   ```

2. **Create Installation Configuration**
   ```bash
   mkdir ~/ocp-install
   
   # Create install-config.yaml
   cat > ~/ocp-install/install-config.yaml << EOF
   apiVersion: v1
   baseDomain: ocp.lan
   compute:
   - hyperthreading: Enabled
     name: worker
     replicas: 3
   controlPlane:
     hyperthreading: Enabled
     name: master
     replicas: 3
   metadata:
     name: lab
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
   
   # Make a backup of the install-config.yaml
   cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml.bak
   ```

3. **Generate Kubernetes Manifests**
   ```bash
   ./openshift-install create manifests --dir=~/ocp-install
   
   # Optional: Make control plane nodes non-schedulable
   sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml
   ```

4. **Generate Ignition Files**
   ```bash
   ./openshift-install create ignition-configs --dir=~/ocp-install
   ```

5. **Host Installation Files**
   ```bash
   # Copy files to web server directory
   cp -R ~/ocp-install/*.ign /var/www/html/ocp4/
   cp ~/rhcos-metal.x86_64.raw.gz /var/www/html/ocp4/rhcos
   
   # Set proper permissions
   chcon -R -t httpd_sys_content_t /var/www/html/ocp4/
   chown -R apache: /var/www/html/ocp4/
   chmod 755 /var/www/html/ocp4/
   ```

### Deploy the Bootstrap and Master Nodes

1. **Create Customized Boot ISOs**
   ```bash
   ./scripts/create-iso.sh bootstrap ocp-bootstrap 192.168.22.200
   ./scripts/create-iso.sh master ocp-cp-1 192.168.22.201
   ./scripts/create-iso.sh master ocp-cp-2 192.168.22.202
   ./scripts/create-iso.sh master ocp-cp-3 192.168.22.203
   ```

2. **Boot the Bootstrap Node**
   - Mount the generated bootstrap ISO
   - Start the VM and wait for installation to complete
   - OR use direct boot parameters:
   ```
   coreos.inst.install_dev=sda coreos.inst.image_url=http://192.168.22.1:8080/ocp4/rhcos coreos.inst.ignition_url=http://192.168.22.1:8080/ocp4/bootstrap.ign ip=192.168.22.200::192.168.22.1:255.255.255.0:ocp-bootstrap.ocp.lan:ens192:none nameserver=192.168.22.1
   ```

3. **Boot the Control Plane Nodes**
   - Mount the generated master ISOs on each VM
   - Start the VMs and wait for installation to complete
   - OR use direct boot parameters:
   ```
   coreos.inst.install_dev=sda coreos.inst.image_url=http://192.168.22.1:8080/ocp4/rhcos coreos.inst.ignition_url=http://192.168.22.1:8080/ocp4/master.ign ip=192.168.22.20X::192.168.22.1:255.255.255.0:ocp-cp-X.ocp.lan:ens192:none nameserver=192.168.22.1
   ```
   (Replace X with the appropriate node number)

### Monitor the Bootstrap Process

1. **Watch the Bootstrap Process**
   ```bash
   ./openshift-install --dir=~/ocp-install wait-for bootstrap-complete --log-level=info
   ```

   This command will monitor the bootstrap process and report when it's complete. This typically takes 15-30 minutes.

2. **Check Cluster Operators**
   ```bash
   export KUBECONFIG=~/ocp-install/auth/kubeconfig
   oc get clusteroperators
   ```

### Deploy Worker Nodes

1. **Create Customized Boot ISOs for Workers**
   ```bash
   ./scripts/create-iso.sh worker ocp-w-1 192.168.22.204
   ./scripts/create-iso.sh worker ocp-w-2 192.168.22.205
   ./scripts/create-iso.sh worker ocp-w-3 192.168.22.206
   ```

2. **Boot the Worker Nodes**
   - Mount the generated worker ISOs on each VM
   - Start the VMs and wait for installation to complete
   - OR use direct boot parameters:
   ```
   coreos.inst.install_dev=sda coreos.inst.image_url=http://192.168.22.1:8080/ocp4/rhcos coreos.inst.ignition_url=http://192.168.22.1:8080/ocp4/worker.ign ip=192.168.22.20X::192.168.22.1:255.255.255.0:ocp-w-X.ocp.lan:ens192:none nameserver=192.168.22.1
   ```
   (Replace X with the appropriate node number)

3. **Approve Certificate Signing Requests**
   - After worker nodes boot, they will generate certificate signing requests (CSRs)
   - These must be approved for the nodes to join the cluster

   ```bash
   # Check for pending CSRs
   oc get csr
   
   # Approve all pending CSRs
   oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve
   
   # You may need to run this command multiple times as new CSRs are generated
   ```

4. **Monitor Node Status**
   ```bash
   watch -n5 oc get nodes
   ```

   Wait until all nodes are in the Ready state.

### Remove the Bootstrap Node

Once the bootstrap process is complete and the control plane is operational, the bootstrap node can be removed:

1. **Remove Bootstrap from Load Balancer Configuration**
   ```bash
   ./scripts/remove-bootstrap.sh
   ```
   
   This script modifies the HAProxy configuration to remove the bootstrap node entries.

2. **Shut Down and Delete the Bootstrap VM**
   - The bootstrap node is no longer needed and can be powered off and deleted

### Configure Storage for the Registry

1. **Create Registry Persistent Volume**
   ```bash
   oc create -f ./configs/registry-pv.yaml
   ```

2. **Configure the Image Registry Operator**
   ```bash
   oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'
   
   # Check that the image-registry-storage PVC bound to our PV
   oc get pvc -n openshift-image-registry
   ```

3. **Set Registry to Managed State**
   ```bash
   oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
   ```

### Create the First Admin User

1. **Create HTPasswd Authentication Provider**
   ```bash
   # Generate password hash
   htpasswd -c -B -b /tmp/htpasswd admin password
   
   # Create authentication secret
   oc create secret generic htpass-secret --from-file=htpasswd=/tmp/htpasswd -n openshift-config
   
   # Apply OAuth configuration
   cat << EOF | oc apply -f -
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
           name: htpass-secret
   EOF
   
   # Assign admin privileges
   oc adm policy add-cluster-role-to-user cluster-admin admin
   ```

### Access the OpenShift Console

1. **Get the Console URL**
   ```bash
   oc get route console -n openshift-console
   ```

2. **Add DNS Record to Your Workstation**
   
   Add the following to your workstation's hosts file:
   ```
   <services-vm-external-ip> console-openshift-console.apps.lab.ocp.lan oauth-openshift.apps.lab.ocp.lan
   ```

3. **Access the Console**
   - Open a web browser and navigate to `https://console-openshift-console.apps.lab.ocp.lan`
   - Log in with the admin user created earlier

## Troubleshooting

For common issues and solutions, see the [Troubleshooting Guide](docs/troubleshooting.md).

## Additional Resources

- [Official OpenShift Documentation](https://docs.openshift.com/container-platform/4.14/installing/installing_bare_metal/installing-bare-metal.html)
- [OpenShift on Bare Metal UPI Blog](https://www.openshift.com/blog/openshift-4-bare-metal-install-quickstart)
- [Red Hat CoreOS Documentation](https://docs.openshift.com/container-platform/4.14/architecture/architecture-rhcos.html)

