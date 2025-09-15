#!/bin/bash

# This script creates the initial admin user for OpenShift
# Adapted for txse.systems environment
# Usage: ./create-admin-user.sh <username> <password>

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    echo "Example: $0 admin password"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

echo "==> Creating admin user: $USERNAME for txse.systems cluster"

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

# Create htpasswd secret
HTPASSWD_DATA=$(htpasswd -nb -B $USERNAME $PASSWORD)

echo "Creating OAuth configuration and HTPasswd secret..."
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
echo "Assigning cluster-admin role to $USERNAME..."
oc adm policy add-cluster-role-to-user cluster-admin $USERNAME

echo "==> User '$USERNAME' created and granted cluster-admin privileges"
echo "Wait a few minutes for the authentication operator to reconcile before attempting to log in"
echo "Console URL: https://console-openshift-console.apps.ocp.txse.systems"
