#!/bin/bash

# Master script to run the complete OpenShift installation process
# for txse.systems environment
# Run this on the services VM (10.18.0.105)

set -e

echo "===== OpenShift 4 Installation on txse.systems ====="
echo "This script will install OpenShift 4 on your data center VMs"
echo "Cluster domain: ocp.txse.systems"
echo "Services VM: 10.18.0.105"
echo

# Ask for confirmation
read -p "Are you ready to proceed? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Installation aborted"
    exit 1
fi

# Create directories
mkdir -p ~/ocp-install ~/downloads /var/www/html/ocp4/{ignition,images}

# Step 1: Setup DNS
echo
echo "===== Step 1: Setting up DNS server ====="
./setup-dns.sh

# Step 2: Setup HAProxy
echo
echo "===== Step 2: Setting up HAProxy load balancer ====="
./setup-haproxy.sh

# Step 3: Setup Web Server
echo
echo "===== Step 3: Setting up Web Server ====="
./setup-webserver.sh

# Step 4: Setup NFS
echo
echo "===== Step 4: Setting up NFS Server ====="
./setup-nfs.sh

# Step 5: Download OpenShift Files
echo
echo "===== Step 5: Downloading OpenShift Files ====="
./download-openshift.sh

# Step 6: Generate Ignition Files
echo
echo "===== Step 6: Generating Ignition Files ====="
./generate-ignition.sh

# Step 7: Boot Nodes
echo
echo "===== Step 7: Ready to Boot Nodes ====="
echo "You must now boot each VM with the RHCOS ISO and appropriate boot parameters"
echo "See node-boot-instructions.md for detailed instructions"
echo
echo "Boot the bootstrap node (10.18.0.10) first, followed by the master nodes (10.18.0.11, 10.18.0.12, 10.18.0.13)"
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
echo "Bootstrap node can now be safely powered off"

# Step 10: Boot Worker Nodes
echo
echo "===== Step 10: Booting Worker Nodes ====="
echo "Please boot your worker nodes now (10.18.0.21, 10.18.0.22, 10.18.0.23) if you haven't already"
echo

read -p "Have you booted the worker nodes? (y/n): " worker_booted
if [ "$worker_booted" != "y" ]; then
    echo "Please boot the worker nodes and then continue"
    exit 1
fi

# Step 11: Approve Worker CSRs
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
./configure-registry.sh

# Step 14: Create Admin User
echo
echo "===== Step 14: Creating Admin User ====="
./create-admin-user.sh admin password

echo
echo "===== Installation Complete ====="
echo "You can now access the OpenShift console at:"
echo "https://console-openshift-console.apps.ocp.txse.systems"
echo
echo "Admin credentials:"
echo "Username: admin"
echo "Password: password"
echo
echo "Enjoy your new OpenShift cluster on txse.systems!"
