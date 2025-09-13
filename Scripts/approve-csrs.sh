#!/bin/bash
# This script approves pending certificate signing requests for worker nodes
# Usage: ./approve-csrs.sh

# Check if we're logged in to the cluster
if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Please export KUBECONFIG and try again."
    echo "Example: export KUBECONFIG=~/ocp-install/auth/kubeconfig"
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
done

