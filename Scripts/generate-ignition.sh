#!/bin/bash

# This script generates the ignition files for the OpenShift installation
# Adapted for txse.systems environment

set -e

echo "==> Generating ignition files for txse.systems"

# Check if pull secret exists
if [ ! -f ~/pull-secret.txt ]; then
    echo "Error: Pull secret not found at ~/pull-secret.txt"
    echo "Please download your pull secret from https://console.redhat.com/openshift/install/pull-secret"
    exit 1
fi

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
fi

# Create install-config.yaml
echo "Creating install-config.yaml..."
cat > ~/ocp-install/install-config.yaml << EOF
apiVersion: v1
baseDomain: txse.systems
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: ocp
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '$(cat ~/pull-secret.txt)'
sshKey: '$(cat ~/.ssh/id_rsa.pub)'
EOF

# Backup the install-config.yaml
cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml.bak

# Generate manifests
echo "Generating manifests..."
openshift-install create manifests --dir=~/ocp-install

# Optional: Make control plane nodes non-schedulable (recommended for production)
echo "Making control plane nodes non-schedulable..."
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g' ~/ocp-install/manifests/cluster-scheduler-02-config.yml

# Generate ignition configs
echo "Generating ignition configs..."
openshift-install create ignition-configs --dir=~/ocp-install

# Copy ignition files to web server directory
echo "Copying ignition files to web server..."
sudo cp ~/ocp-install/*.ign /var/www/html/ocp4/ignition/
sudo chown apache:apache /var/www/html/ocp4/ignition/*.ign
sudo chmod 644 /var/www/html/ocp4/ignition/*.ign

# Verify ignition files are accessible
echo "Verifying ignition files are accessible..."
curl -I http://10.18.0.105:8080/ocp4/ignition/bootstrap.ign

echo "==> Ignition files generated successfully for txse.systems"
echo "Bootstrap ignition: http://10.18.0.105:8080/ocp4/ignition/bootstrap.ign"
echo "Master ignition: http://10.18.0.105:8080/ocp4/ignition/master.ign"
echo "Worker ignition: http://10.18.0.105:8080/ocp4/ignition/worker.ign"
