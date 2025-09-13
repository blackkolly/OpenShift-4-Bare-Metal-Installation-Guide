# OpenShift 4 Bare Metal Installation Troubleshooting Guide

This document provides guidance for troubleshooting common issues that may arise during the OpenShift 4 Bare Metal UPI installation process.

## Table of Contents

- [DNS Issues](#dns-issues)
- [DHCP Issues](#dhcp-issues)
- [HAProxy Issues](#haproxy-issues)
- [Bootstrap Process Issues](#bootstrap-process-issues)
- [Certificate Signing Request Issues](#certificate-signing-request-issues)
- [Registry Storage Issues](#registry-storage-issues)
- [Network Connectivity Issues](#network-connectivity-issues)
- [Logging and Debugging](#logging-and-debugging)

## DNS Issues

DNS is a critical component for OpenShift installation. Problems with DNS resolution are among the most common issues.

### Symptoms
- Nodes fail to pull images during installation
- API server cannot be reached
- Bootstrap process fails with timeout errors
- Services cannot resolve each other

### Troubleshooting Steps

1. **Verify DNS Service is Running**
   ```bash
   systemctl status named
   ```

2. **Check DNS Configuration**
   ```bash
   # Validate named.conf syntax
   named-checkconf /etc/named.conf
   
   # Validate zone files
   named-checkzone ocp.lan /var/named/ocp.lan.db
   named-checkzone 22.168.192.in-addr.arpa /var/named/22.168.192.db
   ```

3. **Test DNS Resolution**
   ```bash
   # Test forward resolution
   dig api.ocp.lan @192.168.22.1
   dig etcd-0.ocp.lan @192.168.22.1
   dig *.apps.ocp.lan @192.168.22.1
   
   # Test reverse resolution
   dig -x 192.168.22.201 @192.168.22.1
   
   # Test SRV records
   dig _etcd-server-ssl._tcp.ocp.lan SRV @192.168.22.1
   ```

4. **Common Fixes**
   - Check for typos in zone files
   - Ensure serial numbers are updated after changes
   - Verify SELinux permissions: `restorecon -rv /var/named`
   - Restart the DNS service: `systemctl restart named`
   - Check firewall settings: `firewall-cmd --list-all --zone=internal`

## DHCP Issues

Problems with DHCP can prevent nodes from getting proper IP addresses and network configuration.

### Symptoms
- Nodes cannot get IP addresses
- Nodes get wrong IP addresses
- Nodes cannot reach the network

### Troubleshooting Steps

1. **Verify DHCP Service is Running**
   ```bash
   systemctl status dhcpd
   ```

2. **Check DHCP Configuration**
   ```bash
   # Validate dhcpd.conf syntax
   dhcpd -t -cf /etc/dhcp/dhcpd.conf
   ```

3. **Check DHCP Leases**
   ```bash
   cat /var/lib/dhcpd/dhcpd.leases
   ```

4. **Check if MAC Addresses Match**
   - Verify that the MAC addresses in dhcpd.conf match the actual MAC addresses of your VMs
   - Update MAC addresses if necessary and restart DHCP: `systemctl restart dhcpd`

5. **Monitor DHCP Requests**
   ```bash
   # Monitor DHCP traffic
   tcpdump -i ens224 port 67 or port 68 -n
   ```

## HAProxy Issues

HAProxy provides load balancing for the API and Ingress services.

### Symptoms
- Cannot access the API server (port 6443)
- Cannot access machine config server (port 22623)
- Cannot access applications after installation
- HAProxy service fails to start

### Troubleshooting Steps

1. **Verify HAProxy Service is Running**
   ```bash
   systemctl status haproxy
   ```

2. **Check HAProxy Configuration**
   ```bash
   # Validate haproxy.cfg syntax
   haproxy -c -f /etc/haproxy/haproxy.cfg
   ```

3. **Check HAProxy Stats**
   - Access the HAProxy stats page: `http://<services-vm-ip>:9000/`
   - Check the status of backends and servers

4. **Test Connectivity to Backend Servers**
   ```bash
   # Test connection to API server
   nc -zv 192.168.22.201 6443
   
   # Test connection to machine config server
   nc -zv
