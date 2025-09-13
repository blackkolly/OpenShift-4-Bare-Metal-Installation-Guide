#!/bin/bash
# This script sets up all required services on the services VM
# Run as root

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Install required packages
echo "Installing required packages..."
dnf update -y
dnf install -y bind bind-utils dhcp-server haproxy httpd nfs-utils firewalld bash-completion vim wget git jq net-tools htpasswd

# Set up network zones
echo "Configuring network zones..."
# Assuming ens192 is external and ens224 is internal
nmcli connection modify ens192 connection.zone external
nmcli connection modify ens224 connection.zone internal

# Configure masquerading for both zones
firewall-cmd --zone=external --add-masquerade --permanent
firewall-cmd --zone=internal --add-masquerade --permanent

# Configure services directory structure
echo "Creating directories..."
mkdir -p /var/www/html/ocp4
mkdir -p /var/named
mkdir -p /shares/registry

# Configure DNS
echo "Configuring DNS..."
cp ./configs/named.conf /etc/named.conf
cp ./configs/dns/ocp.lan.db /var/named/
cp ./configs/dns/22.168.192.db /var/named/
chown -R named:named /var/named

# Configure DHCP
echo "Configuring DHCP..."
cp ./configs/dhcpd.conf /etc/dhcp/dhcpd.conf

# Configure HAProxy
echo "Configuring HAProxy..."
cp ./configs/haproxy.cfg /etc/haproxy/haproxy.cfg
setsebool -P haproxy_connect_any 1

# Configure Apache
echo "Configuring Apache..."
sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf

# Configure NFS
echo "Configuring NFS..."
chown -R nobody:nobody /shares/registry
chmod -R 777 /shares/registry
echo "/shares/registry  192.168.22.0/24(rw,sync,root_squash,no_subtree_check,no_wdelay)" > /etc/exports
exportfs -rv

# Configure firewall rules
echo "Configuring firewall..."
# DNS
firewall-cmd --add-port=53/udp --zone=internal --permanent
firewall-cmd --add-port=53/tcp --zone=internal --permanent

# DHCP
firewall-cmd --add-service=dhcp --zone=internal --permanent

# HTTP
firewall-cmd --add-port=8080/tcp --zone=internal --permanent

# HAProxy
firewall-cmd --add-port=6443/tcp --zone=internal --permanent
firewall-cmd --add-port=6443/tcp --zone=external --permanent
firewall-cmd --add-port=22623/tcp --zone=internal --permanent
firewall-cmd --add-service=http --zone=internal --permanent
firewall-cmd --add-service=http --zone=external --permanent
firewall-cmd --add-service=https --zone=internal --permanent
firewall-cmd --add-service=https --zone=external --permanent
firewall-cmd --add-port=9000/tcp --zone=external --permanent

# NFS
firewall-cmd --zone=internal --add-service=mountd --permanent
firewall-cmd --zone=internal --add-service=rpc-bind --permanent
firewall-cmd --zone=internal --add-service=nfs --permanent

# Apply firewall rules
firewall-cmd --reload

# Start and enable services
echo "Starting services..."
systemctl enable --now named
systemctl enable --now dhcpd
systemctl enable --now httpd
systemctl enable --now haproxy
systemctl enable --now nfs-server rpcbind

# Set proper permissions for web server
chcon -R -t httpd_sys_content_t /var/www/html/ocp4/
chown -R apache: /var/www/html/ocp4/
chmod 755 /var/www/html/ocp4/

echo "Services setup complete!"
echo "Next steps:"
echo "1. Copy RHCOS ISO and RAW images to /var/www/html/ocp4/"
echo "2. Generate ignition configs and copy to /var/www/html/ocp4/"

