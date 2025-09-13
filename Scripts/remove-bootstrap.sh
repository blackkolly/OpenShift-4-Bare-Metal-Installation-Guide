#!/bin/bash
# This script removes bootstrap node references from HAProxy
# Usage: ./remove-bootstrap.sh

# Backup the existing HAProxy configuration
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
BACKUP_FILE="${HAPROXY_CFG}.bak.$(date +%Y%m%d-%H%M%S)"

echo "Backing up HAProxy configuration to $BACKUP_FILE"
cp $HAPROXY_CFG $BACKUP_FILE

# Remove bootstrap entries from the configuration
echo "Removing bootstrap node from HAProxy configuration..."
sed -i '/server ocp-bootstrap /d' $HAPROXY_CFG

# Validate the configuration
echo "Validating HAProxy configuration..."
haproxy -c -f $HAPROXY_CFG

if [ $? -eq 0 ]; then
    echo "HAProxy configuration is valid. Reloading service..."
    systemctl reload haproxy
    
    if [ $? -eq 0 ]; then
        echo "HAProxy service reloaded successfully."
    else
        echo "ERROR: Failed to reload HAProxy service. Please check logs."
        exit 1
    fi
else
    echo "ERROR: HAProxy configuration is invalid. Restoring backup..."
    cp $BACKUP_FILE $HAPROXY_CFG
    exit 1
fi

echo "Bootstrap node removed from HAProxy configuration."
echo "You can now safely shut down and delete the bootstrap VM."

