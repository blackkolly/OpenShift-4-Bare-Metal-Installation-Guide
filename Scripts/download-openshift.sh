#!/bin/bash

# This script downloads the required OpenShift files
# including the installer, client, and RHCOS images
# Adapted for txse.systems environment

set -e

echo "==> Downloading OpenShift files for txse.systems deployment"

# Create directories
mkdir -p ~/ocp-install ~/downloads

# Download OpenShift client and installer
echo "Downloading OpenShift client and installer..."
wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -O ~/downloads/openshift-client-linux.tar.gz
wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz -O ~/downloads/openshift-install-linux.tar.gz

# Extract client and installer
echo "Extracting client and installer..."
tar -xzf ~/downloads/openshift-client-linux.tar.gz -C ~/downloads
tar -xzf ~/downloads/openshift-install-linux.tar.gz -C ~/downloads

# Move binaries to PATH
sudo mv ~/downloads/oc ~/downloads/kubectl /usr/local/bin/
sudo mv ~/downloads/openshift-install /usr/local/bin/

# Verify installation
echo "Verifying installation..."
oc version
openshift-install version

# Create web directories
sudo mkdir -p /var/www/html/ocp4/{ignition,images}
sudo chown -R apache:apache /var/www/html/ocp4
sudo chmod -R 755 /var/www/html/ocp4

# Get RHCOS version from the installer
RHCOS_VERSION=$(openshift-install version | grep -oP 'release image.*CoreOS: \K[0-9.]+')
echo "RHCOS version: $RHCOS_VERSION"

# Download RHCOS images
echo "Downloading RHCOS images..."
BASEURL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_VERSION:0:4}/${RHCOS_VERSION}"

wget -q $BASEURL/rhcos-$RHCOS_VERSION-x86_64-live.x86_64.iso -O /var/www/html/ocp4/images/rhcos-live.iso
wget -q $BASEURL/rhcos-$RHCOS_VERSION-x86_64-metal.x86_64.raw.gz -O /var/www/html/ocp4/images/rhcos-metal.raw.gz

# Set permissions
sudo chown apache:apache /var/www/html/ocp4/images/*

echo "==> OpenShift files downloaded successfully"
echo "RHCOS images available at: http://10.18.0.105:8080/ocp4/images/"
