#!/bin/bash
# This script monitors the OpenShift bootstrap process
# Usage: ./monitor-bootstrap.sh

# Check for installation directory
INSTALL_DIR=~/ocp-install
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Installation directory not found at $INSTALL_DIR"
    exit 1
fi

# Monitor bootstrap process
echo "Monitoring bootstrap process. This may take 20-30 minutes..."
~/openshift-install --dir=$INSTALL_DIR wait-for bootstrap-complete --log-level=info

