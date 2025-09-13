#!/bin/bash

# This script creates custom boot ISO files for OpenShift nodes
# Usage: ./create-iso.sh <node_type> <node_name> <node_ip>

# Check if correct arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <node_type> <node_name> <node_ip>"
    echo "Example: $0 master ocp-cp-1 192.168.22.201"
    exit 1
fi

NODE_TYPE=$1
NODE_NAME=$2
NODE_IP=$3

# Source ISO path (adjust the path to your RHCOS ISO)
SOURCE_ISO="/var/www/html/ocp4/rhcos-live.x86_64.iso"
OUTPUT_ISO="/var/www/html/ocp4/isos/${NODE_NAME}.iso"

# Create ISO directory if it doesn't exist
mkdir -p /var/www/html/ocp4/isos

# Create temporary workspace
TEMPDIR=$(mktemp -d)
ISO_MOUNT="${TEMPDIR}/iso"
NEW_ISO="${TEMPDIR}/new"
mkdir -p "${ISO_MOUNT}" "${NEW_ISO}"

# Mount the original ISO
sudo mount -o loop "${SOURCE_ISO}" "${ISO_MOUNT}"

# Copy all contents
cp -a "${ISO_MOUNT}"/* "${NEW_ISO}/"
cp -a "${ISO_MOUNT}"/.treeinfo "${NEW_ISO}/" 2>/dev/null || true

# Determine ignition URL based on node type
if [ "${NODE_TYPE}" == "bootstrap" ]; then
    IGNITION_URL="http://192.168.22.1:8080/ocp4/bootstrap.ign"
elif [ "${NODE_TYPE}" == "master" ]; then
    IGNITION_URL="http://192.168.22.1:8080/ocp4/master.ign"
elif [ "${NODE_TYPE}" == "worker" ]; then
    IGNITION_URL="http://192.168.22.1:8080/ocp4/worker.ign"
else
    echo "Invalid node type. Must be bootstrap, master, or worker"
    exit 1
fi

# Modify grub.cfg to include our boot parameters
if [ -f "${NEW_ISO}/EFI/redhat/grub.cfg" ]; then
    # Make a backup of the original file
    cp "${NEW_ISO}/EFI/redhat/grub.cfg" "${NEW_ISO}/EFI/redhat/grub.cfg.orig"
    
    # Modify the grub.cfg file to include our parameters
    sed -i "s|options |options ip=${NODE_IP}::192.168.22.1:255.255.255.0:${NODE_NAME}.ocp.lan:ens192:none nameserver=192.168.22.1 coreos.inst.install_dev=sda coreos.inst.image_url=http://192.168.22.1:8080/ocp4/rhcos coreos.inst.ignition_url=${IGNITION_URL} |g" "${NEW_ISO}/EFI/redhat/grub.cfg"
fi

# Modify isolinux.cfg if it exists
if [ -f "${NEW_ISO}/isolinux/isolinux.cfg" ]; then
    # Make a backup of the original file
    cp "${NEW_ISO}/isolinux/isolinux.cfg" "${NEW_ISO}/isolinux/isolinux.cfg.orig"
    
    # Modify the isolinux.cfg file to include our parameters
    sed -i "s|append |append ip=${NODE_IP}::192.168.22.1:255.255.255.0:${NODE_NAME}.ocp.lan:ens192:none nameserver=192.168.22.1 coreos.inst.install_dev=sda coreos.inst.image_url=http://192.168.22.1:8080/ocp4/rhcos coreos.inst.ignition_url=${IGNITION_URL} |g" "${NEW_ISO}/isolinux/isolinux.cfg"
fi

# Create the new ISO
if [ -f "${NEW_ISO}/isolinux/isolinux.bin" ]; then
    # Using isolinux for legacy BIOS boot
    mkisofs -o "${OUTPUT_ISO}" \
        -b isolinux/isolinux.bin -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
        -R -J -V "RHCOS-custom" \
        "${NEW_ISO}"
    isohybrid --uefi "${OUTPUT_ISO}" 2>/dev/null || true
else
    # EFI-only boot
    mkisofs -o "${OUTPUT_ISO}" \
        -e images/efiboot.img -no-emul-boot \
        -R -J -V "RHCOS-custom" \
        "${NEW_ISO}"
fi

# Clean up
sudo umount "${ISO_MOUNT}"
rm -rf "${TEMPDIR}"

echo "Custom ISO created at ${OUTPUT_ISO}"


