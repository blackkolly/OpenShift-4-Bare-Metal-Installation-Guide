#!/bin/bash

# This script configures storage for the OpenShift image registry
# Adapted for txse.systems environment

set -e

echo "==> Configuring storage for the OpenShift image registry"

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

# Create the registry PV
echo "Creating the registry persistent volume..."
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

# Wait for PV to be created
echo "Waiting for registry PV to be created..."
sleep 5

# Configure the image registry operator
echo "Configuring Image Registry Operator..."
oc patch configs.imageregistry.operator.openshift.io cluster --type=merge --patch '{"spec":{"managementState":"Managed"}}'
oc patch configs.imageregistry.operator.openshift.io cluster --type=merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'

# Wait for the PVC to be created
echo "Waiting for registry PVC to be created..."
sleep 10

# Verify that the PVC is bound
PVC_STATUS=$(oc get pvc -n openshift-image-registry | grep image-registry-storage | awk '{print $2}')
if [ "$PVC_STATUS" == "Bound" ]; then
    echo "Registry PVC bound successfully!"
else
    echo "Registry PVC not bound. Current status: $PVC_STATUS"
    echo "Check events with: oc get events -n openshift-image-registry"
fi

# Display registry pod status
echo "Registry pod status:"
oc get pods -n openshift-image-registry

echo "==> Registry configuration completed"
