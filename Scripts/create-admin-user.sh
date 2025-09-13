#!/bin/bash
# This script creates the initial admin user for OpenShift
# Usage: ./create-admin-user.sh <username> <password>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    echo "Example: $0 admin password"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

# Check if we're logged in to the cluster
if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Please export KUBECONFIG and try again."
    echo "Example: export KUBECONFIG=~/ocp-install/auth/kubeconfig"
    exit 1
fi

# Create htpasswd data
HTPASSWD_DATA=$(htpasswd -nb -B $USERNAME $PASSWORD)

# Create authentication resources
cat <<EOFAUTH | oc apply -f -
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
EOFAUTH

# Assign cluster-admin role to the user
oc adm policy add-cluster-role-to-user cluster-admin $USERNAME

echo "User '$USERNAME' created and granted cluster-admin privileges."
echo "Wait a few minutes for the authentication operator to reconcile before attempting to log in."

