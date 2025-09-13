#!/bin/bash
# This script configures storage for the OpenShift image registry
# Usage: ./setup-registry.sh

# Check if we're logged in to the cluster
if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Please export KUBECONFIG and try again."
    echo "Example: export KUBECONFIG=~/ocp-install/auth/kubeconfig"
    exit 1
fi

# Create the registry PV
cat <<EOFPV | oc create -f -
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
    path: /shares/registry
    server: 192.168.22.1
EOFPV

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

