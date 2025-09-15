# OpenShift Node Boot Instructions for txse.systems

This document provides instructions for booting the OpenShift nodes (bootstrap, masters, and workers) on the txse.systems environment.

## Prerequisites

1. Ensure the services VM (10.18.0.105) is properly configured with DNS, HAProxy, web server, and NFS
2. Verify that the RHCOS ISO and metal image are available on the web server
3. Confirm that the ignition files have been generated and are accessible via the web server

## Instructions for Each Node Type

### Bootstrap Node (10.18.0.10)

1. Mount the RHCOS ISO on the bootstrap VM
2. Boot from the ISO
3. At the boot prompt, press TAB to edit the kernel parameters
4. Add the following parameters:coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/bootstrap.ign ip=10.18.0.10::10.18.0.1:255.255.255.0:bootstrap.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

5. 5. Press Enter to boot with these parameters
6. The installation will proceed automatically
7. The VM will reboot after installation and start the bootstrap process

### Master Nodes

#### Master-1 (10.18.0.11)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:

4. 
#### Master-2 (10.18.0.12)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:
   coreos.inst.install_dev=sda
   coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz
 #### Master-3 (10.18.0.13)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:
 coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/master.ign ip=10.18.0.13::10.18.0.1:255.255.255.0:master-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

### Worker Nodes

#### Worker-1 (10.18.0.21)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.21::10.18.0.1:255.255.255.0:worker-1.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

#### Worker-2 (10.18.0.22)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.22::10.18.0.1:255.255.255.0:worker-2.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

#### Worker-3 (10.18.0.23)

1. Mount the RHCOS ISO on the VM
2. Boot from the ISO
3. At the boot prompt, press TAB and add the following parameters:
coreos.inst.install_dev=sda coreos.inst.image_url=http://10.18.0.105:8080/ocp4/images/rhcos-metal.raw.gz coreos.inst.ignition_url=http://10.18.0.105:8080/ocp4/ignition/worker.ign ip=10.18.0.23::10.18.0.1:255.255.255.0:worker-3.ocp.txse.systems:mgmt0:none nameserver=10.18.0.105

## Verifying Node Installation

### Check Bootstrap Progress

On the services VM (10.18.0.105), run:
```bash
export KUBECONFIG=~/ocp-install/auth/kubeconfig
openshift-install --dir=~/ocp-install wait-for bootstrap-complete --log-level=info

Check Node Status
bashexport KUBECONFIG=~/ocp-install/auth/kubeconfig
oc get nodes
Check Cluster Operators
bashoc get co
Notes for txse.systems Environment

Make sure to use the correct interface name mgmt0 in all boot parameters
The gateway IP is assumed to be 10.18.0.1 - adjust if different
All nodes should be configured to use the services VM (10.18.0.105) as their DNS server


## approve-csrs.sh
```bash
#!/bin/bash

# This script approves pending certificate signing requests for worker nodes
# Adapted for txse.systems environment
# Usage: ./approve-csrs.sh

set -e

echo "==> Worker node CSR approval script for txse.systems cluster"

# Check if KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    # Try to set it from the default location
    if [ -f ~/ocp-install/auth/kubeconfig ]; then
        export KUBECONFIG=~/ocp-install/auth/kubeconfig
        echo "KUBECONFIG set to ~/ocp-install/auth/kubeconfig"
    else
        echo "Error: KUBECONFIG not set and default location not found"
        echo "Please export KUBECONFIG=~/ocp-install/auth/kubeconfig"
        exit 1
    fi
fi

# Check if we're logged in to the cluster
if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Please check your KUBECONFIG"
    exit 1
fi

# Function to approve all pending CSRs
approve_csrs() {
    PENDING_CSRS=$(oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
    
    if [ -z "$PENDING_CSRS" ]; then
        echo "No pending CSRs found."
        return
    fi
    
    echo "Approving CSRs:"
    echo "$PENDING_CSRS"
    
    for CSR in $PENDING_CSRS; do
        oc adm certificate approve $CSR
    done
}

# Main loop to keep checking for CSRs
echo "Watching for pending CSRs. Press Ctrl+C to stop."
while true; do
    approve_csrs
    echo "Sleeping for 10 seconds..."
    sleep 10
    echo "Checking node status:"
    oc get nodes
done
