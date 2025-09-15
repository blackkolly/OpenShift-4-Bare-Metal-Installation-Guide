# OpenShift Cluster Deletion Script

This script helps you completely remove an OpenShift installation from your txse.systems environment. It will clean up all components on all servers.

## cleanup-all-servers.sh

```bash
#!/bin/bash

# OpenShift Cluster Deletion Script for txse.systems
# This script removes all OpenShift components from all servers in the cluster

set -e

echo "===== OpenShift 4 Cluster Deletion for txse.systems ====="
echo "WARNING: This script will completely remove all OpenShift components"
echo "         and associated data from ALL servers in your cluster."
echo
echo "The following will be deleted:"
echo "- All OpenShift services and components"
echo "- All persistent data (including registry storage)"
echo "- All configuration files and ignition files"
echo "- All DNS, DHCP, HAProxy, and web server configurations"
echo
echo "This is a DESTRUCTIVE operation and CANNOT be undone!"
echo

# Ask for confirmation
read -p "Are you sure you want to proceed with deletion? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deletion aborted"
    exit 1
fi

echo "Proceeding with deletion..."

# Define server IPs
SERVICES_IP="10.18.0.105"
BOOTSTRAP_IP="10.18.0.10"
MASTER1_IP="10.18.0.11"
MASTER2_IP="10.18.0.12"
MASTER3_IP="10.18.0.13"
WORKER1_IP="10.18.0.21"
WORKER2_IP="10.18.0.22"
WORKER3_IP="10.18.0.23"

# SSH key and user for connections
SSH_USER="core"
SERVICES_SSH_USER="ocpadmin"  # Adjust if different

# Function to check if host is reachable
check_host() {
    if ping -c 1 -W 1 $1 &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop and disable services on services VM
cleanup_services_vm() {
    echo "===== Cleaning up Services VM ($SERVICES_IP) ====="
    
    # Connect to services VM and execute cleanup
    ssh -o StrictHostKeyChecking=no $SERVICES_SSH_USER@$SERVICES_IP << 'EOF'
        echo "Stopping and disabling services..."
        sudo systemctl stop haproxy || true
        sudo systemctl disable haproxy || true
        sudo systemctl stop httpd || true
        sudo systemctl disable httpd || true
        sudo systemctl stop named || true
        sudo systemctl disable named || true
        sudo systemctl stop nfs-server || true
        sudo systemctl disable nfs-server || true
        sudo systemctl stop dhcpd || true
        sudo systemctl disable dhcpd || true
        
        echo "Removing NFS exports..."
        sudo exportfs -ua || true
        sudo rm -f /etc/exports || true
        sudo rm -rf /exports/* || true
        
        echo "Removing DNS configuration..."
        sudo rm -f /etc/named.conf || true
        sudo rm -f /var/named/ocp.txse.systems.db || true
        sudo rm -f /var/named/0.18.10.db || true
        
        echo "Removing HAProxy configuration..."
        sudo rm -f /etc/haproxy/haproxy.cfg || true
        
        echo "Removing web server content..."
        sudo rm -rf /var/www/html/ocp4 || true
        
        echo "Removing OpenShift installation files..."
        rm -rf ~/ocp-install || true
        rm -rf ~/downloads || true
        
        echo "Removing KUBECONFIG environment variable..."
        unset KUBECONFIG
        sed -i '/KUBECONFIG/d' ~/.bashrc || true
        
        echo "Services VM cleanup completed."
EOF
    
    echo "Services VM cleanup completed."
}

# Function to shutdown and reset a CoreOS node
cleanup_coreos_node() {
    NODE_IP=$1
    NODE_NAME=$2
    
    echo "===== Cleaning up $NODE_NAME ($NODE_IP) ====="
    
    if ! check_host $NODE_IP; then
        echo "$NODE_NAME is not reachable. Skipping..."
        return
    fi
    
    # Connect to node and execute cleanup
    ssh -o StrictHostKeyChecking=no $SSH_USER@$NODE_IP << 'EOF'
        echo "Stopping all OpenShift services..."
        sudo systemctl stop kubelet || true
        sudo systemctl disable kubelet || true
        sudo systemctl stop crio || true
        sudo systemctl disable crio || true
        
        echo "Removing OpenShift directories..."
        sudo rm -rf /etc/kubernetes || true
        sudo rm -rf /var/lib/kubelet || true
        sudo rm -rf /var/lib/containers || true
        sudo rm -rf /var/lib/etcd || true
        sudo rm -rf /var/lib/cni || true
        
        echo "Unmounting OpenShift volumes..."
        sudo umount /var/lib/kubelet || true
        sudo umount /var/lib/containers || true
EOF
    
    echo "$NODE_NAME cleanup completed. Ready for shutdown."
}

# Function to shutdown a VM
shutdown_vm() {
    NODE_IP=$1
    NODE_NAME=$2
    
    echo "Shutting down $NODE_NAME ($NODE_IP)..."
    
    if ! check_host $NODE_IP; then
        echo "$NODE_NAME is not reachable. Skipping shutdown..."
        return
    fi
    
    ssh -o StrictHostKeyChecking=no $SSH_USER@$NODE_IP "sudo shutdown -h now" || true
    
    echo "Shutdown command sent to $NODE_NAME."
}

# Main cleanup sequence

# 1. First, clean up worker nodes
for NODE_IP in $WORKER1_IP $WORKER2_IP $WORKER3_IP; do
    NODE_NAME="worker-$(echo $NODE_IP | cut -d. -f4)"
    cleanup_coreos_node $NODE_IP $NODE_NAME
    shutdown_vm $NODE_IP $NODE_NAME
done

# 2. Clean up master nodes
for NODE_IP in $MASTER1_IP $MASTER2_IP $MASTER3_IP; do
    NODE_NAME="master-$(echo $NODE_IP | cut -d. -f4 | sed 's/^1/1/')"
    cleanup_coreos_node $NODE_IP $NODE_NAME
    shutdown_vm $NODE_IP $NODE_NAME
done

# 3. Clean up bootstrap node if it exists
if check_host $BOOTSTRAP_IP; then
    cleanup_coreos_node $BOOTSTRAP_IP "bootstrap"
    shutdown_vm $BOOTSTRAP_IP "bootstrap"
else
    echo "Bootstrap node is not reachable. Skipping..."
fi

# 4. Clean up services VM
cleanup_services_vm

echo
echo "===== OpenShift Cluster Deletion Complete ====="
echo
echo "All OpenShift components have been removed from all servers."
echo "You can now power off the VMs or reinstall the cluster."
echo 
echo "To reset all VMs completely, you should:"
echo "1. Power off all VMs"
echo "2. Delete or reformat their disks"
echo "3. Reinstall the operating systems if needed"
echo
```

## vm-reset-instructions.md

```markdown
# VM Reset Instructions for txse.systems OpenShift Cluster

After running the `cleanup-all-servers.sh` script, you may want to completely reset your VMs to start fresh. This document provides instructions for completely resetting all VMs in your OpenShift cluster.

## Complete VM Reset Process

### Option 1: Redeploy VMs

If you have automation in place to deploy VMs, the cleanest approach is to:

1. Power off all VMs
2. Delete all VMs
3. Redeploy fresh VMs with the same IPs and names

### Option 2: Reinstall Operating Systems

If you want to keep the same VMs but start with fresh OS installations:

1. For RHCOS nodes (bootstrap, masters, workers):
   - Boot from RHCOS ISO
   - Reinstall with a clean ignition file or no ignition file
   
2. For the services VM:
   - Boot from CentOS/RHEL/Rocky Linux ISO
   - Reinstall the operating system
   - Configure networking with the same IP (10.18.0.105)

### Option 3: Reset Existing VMs

If you want to keep the existing VMs and operating systems but clear OpenShift-related data:

#### For the Services VM (10.18.0.105):

1. Reset service configurations:
```bash
# Reset DNS
sudo systemctl stop named
sudo rm -f /etc/named.conf
sudo rm -f /var/named/ocp.txse.systems.db
sudo rm -f /var/named/0.18.10.db

# Reset HAProxy
sudo systemctl stop haproxy
sudo cp /etc/haproxy/haproxy.cfg.orig /etc/haproxy/haproxy.cfg || sudo rm -f /etc/haproxy/haproxy.cfg

# Reset web server
sudo systemctl stop httpd
sudo rm -rf /var/www/html/ocp4

# Reset NFS
sudo systemctl stop nfs-server
sudo exportfs -ua
sudo rm -f /etc/exports
sudo rm -rf /exports/*
```

2. Remove installation files:
```bash
rm -rf ~/ocp-install
rm -rf ~/downloads
```

#### For RHCOS Nodes (bootstrap, masters, workers):

For these nodes, the best approach is to reinstall the OS since RHCOS is designed to be immutable. However, if you need to reset them without reinstalling:

1. Boot into emergency mode (add `rd.break` to kernel parameters)
2. Mount the filesystem as read-write:
```bash
mount -o remount,rw /sysroot
chroot /sysroot
```

3. Remove OpenShift directories:
```bash
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/containers
rm -rf /var/lib/etcd
rm -rf /var/lib/cni
```

4. Reset network configuration if needed:
```bash
rm -rf /etc/NetworkManager/system-connections/*
```

5. Reboot the system:
```bash
exit
exit
reboot
```

## Server-Specific Reset Instructions

### Services VM (10.18.0.105)

After running the cleanup script, you can either:

1. Reinstall the operating system, or
2. Create a fresh user account and remove OpenShift-related configurations:
```bash
sudo userdel -r ocpadmin
sudo rm -rf /home/ocpadmin
```

### Bootstrap Node (10.18.0.10)

This node is temporary and can be completely removed after installation. If you're starting over:

1. Power off the VM
2. Delete it or revert to a clean snapshot
3. Create a new VM with the same specifications when needed

### Master Nodes (10.18.0.11, 10.18.0.12, 10.18.0.13)

These nodes contain critical cluster data. After running the cleanup script:

1. Power off the VMs
2. Create new VMs with the same specifications or reinstall RHCOS

### Worker Nodes (10.18.0.21, 10.18.0.22, 10.18.0.23)

These nodes are more stateless than the control plane. After running the cleanup script:

1. Power off the VMs
2. Create new VMs with the same specifications or reinstall RHCOS

## After Resetting

Once all VMs have been reset, you can follow the OpenShift installation guide from the beginning to redeploy your cluster.
```

## server-specific-cleanup.sh

```bash
#!/bin/bash

# Server-Specific Cleanup Script for txse.systems OpenShift Cluster
# This script allows you to clean up individual servers in the cluster

set -e

echo "===== OpenShift Server-Specific Cleanup for txse.systems ====="
echo "This script allows you to clean up individual servers in the cluster."
echo

# Display server options
echo "Available servers:"
echo "1. Services VM (10.18.0.105)"
echo "2. Bootstrap Node (10.18.0.10)"
echo "3. Master-1 Node (10.18.0.11)"
echo "4. Master-2 Node (10.18.0.12)"
echo "5. Master-3 Node (10.18.0.13)"
echo "6. Worker-1 Node (10.18.0.21)"
echo "7. Worker-2 Node (10.18.0.22)"
echo "8. Worker-3 Node (10.18.0.23)"
echo "9. All Master Nodes"
echo "10. All Worker Nodes"
echo "11. All Nodes (except Services VM)"
echo "12. Exit"
echo

# Ask for server selection
read -p "Enter the number of the server to clean up: " server_choice

# SSH key and user for connections
SSH_USER="core"
SERVICES_SSH_USER="ocpadmin"  # Adjust if different

# Function to check if host is reachable
check_host() {
    if ping -c 1 -W 1 $1 &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to clean up services VM
cleanup_services_vm() {
    echo "===== Cleaning up Services VM (10.18.0.105) ====="
    
    # Connect to services VM and execute cleanup
    ssh -o StrictHostKeyChecking=no $SERVICES_SSH_USER@10.18.0.105 << 'EOF'
        echo "Stopping and disabling services..."
        sudo systemctl stop haproxy || true
        sudo systemctl disable haproxy || true
        sudo systemctl stop httpd || true
        sudo systemctl disable httpd || true
        sudo systemctl stop named || true
        sudo systemctl disable named || true
        sudo systemctl stop nfs-server || true
        sudo systemctl disable nfs-server || true
        sudo systemctl stop dhcpd || true
        sudo systemctl disable dhcpd || true
        
        echo "Removing NFS exports..."
        sudo exportfs -ua || true
        sudo rm -f /etc/exports || true
        sudo rm -rf /exports/* || true
        
        echo "Removing DNS configuration..."
        sudo rm -f /etc/named.conf || true
        sudo rm -f /var/named/ocp.txse.systems.db || true
        sudo rm -f /var/named/0.18.10.db || true
        
        echo "Removing HAProxy configuration..."
        sudo rm -f /etc/haproxy/haproxy.cfg || true
        
        echo "Removing web server content..."
        sudo rm -rf /var/www/html/ocp4 || true
        
        echo "Removing OpenShift installation files..."
        rm -rf ~/ocp-install || true
        rm -rf ~/downloads || true
        
        echo "Removing KUBECONFIG environment variable..."
        unset KUBECONFIG
        sed -i '/KUBECONFIG/d' ~/.bashrc || true
        
        echo "Services VM cleanup completed."
EOF
    
    echo "Services VM cleanup completed."
}

# Function to clean up a CoreOS node
cleanup_coreos_node() {
    NODE_IP=$1
    NODE_NAME=$2
    
    echo "===== Cleaning up $NODE_NAME ($NODE_IP) ====="
    
    if ! check_host $NODE_IP; then
        echo "$NODE_NAME is not reachable. Skipping..."
        return
    fi
    
    # Connect to node and execute cleanup
    ssh -o StrictHostKeyChecking=no $SSH_USER@$NODE_IP << 'EOF'
        echo "Stopping all OpenShift services..."
        sudo systemctl stop kubelet || true
        sudo systemctl disable kubelet || true
        sudo systemctl stop crio || true
        sudo systemctl disable crio || true
        
        echo "Removing OpenShift directories..."
        sudo rm -rf /etc/kubernetes || true
        sudo rm -rf /var/lib/kubelet || true
        sudo rm -rf /var/lib/containers || true
        sudo rm -rf /var/lib/etcd || true
        sudo rm -rf /var/lib/cni || true
        
        echo "Unmounting OpenShift volumes..."
        sudo umount /var/lib/kubelet || true
        sudo umount /var/lib/containers || true
EOF
    
    echo "$NODE_NAME cleanup completed. Would you like to shutdown this node? (y/n)"
    read shutdown_choice
    if [ "$shutdown_choice" == "y" ]; then
        ssh -o StrictHostKeyChecking=no $SSH_USER@$NODE_IP "sudo shutdown -h now" || true
        echo "Shutdown command sent to $NODE_NAME."
    fi
}

# Clean up based on selection
case $server_choice in
    1)
        cleanup_services_vm
        ;;
    2)
        cleanup_coreos_node "10.18.0.10" "Bootstrap Node"
        ;;
    3)
        cleanup_coreos_node "10.18.0.11" "Master-1 Node"
        ;;
    4)
        cleanup_coreos_node "10.18.0.12" "Master-2 Node"
        ;;
    5)
        cleanup_coreos_node "10.18.0.13" "Master-3 Node"
        ;;
    6)
        cleanup_coreos_node "10.18.0.21" "Worker-1 Node"
        ;;
    7)
        cleanup_coreos_node "10.18.0.22" "Worker-2 Node"
        ;;
    8)
        cleanup_coreos_node "10.18.0.23" "Worker-3 Node"
        ;;
    9)
        cleanup_coreos_node "10.18.0.11" "Master-1 Node"
        cleanup_coreos_node "10.18.0.12" "Master-2 Node"
        cleanup_coreos_node "10.18.0.13" "Master-3 Node"
        ;;
    10)
        cleanup_coreos_node "10.18.0.21" "Worker-1 Node"
        cleanup_coreos_node "10.18.0.22" "Worker-2 Node"
        cleanup_coreos_node "10.18.0.23" "Worker-3 Node"
        ;;
    11)
        cleanup_coreos_node "10.18.0.10" "Bootstrap Node"
        cleanup_coreos_node "10.18.0.11" "Master-1 Node"
        cleanup_coreos_node "10.18.0.12" "Master-2 Node"
        cleanup_coreos_node "10.18.0.13" "Master-3 Node"
        cleanup_coreos_node "10.18.0.21" "Worker-1 Node"
        cleanup_coreos_node "10.18.0.22" "Worker-2 Node"
        cleanup_coreos_node "10.18.0.23" "Worker-3 Node"
        ;;
    12)
        echo "Exiting without any cleanup."
        exit 0
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

echo
echo "===== Cleanup Complete ====="
echo
```
