#!/bin/bash

# Test SSH connection to new Debian 12 server
# Usage: LINODE_IP=xxx.xxx.xxx.xxx LINODE_ROOT_PASSWORD=yourpassword ./test-ssh.sh

set -e  # Exit on any error

# Check required environment variables
if [ -z "$LINODE_IP" ]; then
    echo "Error: LINODE_IP environment variable not set"
    exit 1
fi

if [ -z "$LINODE_ROOT_PASSWORD" ]; then
    echo "Error: LINODE_ROOT_PASSWORD environment variable not set"
    exit 1
fi

echo "Testing SSH connection to $LINODE_IP as root..."

# Use sshpass to provide password (install with: brew install sshpass on Mac, apt install sshpass on Linux)
sshpass -p "$LINODE_ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$LINODE_IP "uname -a && echo 'SSH connection successful!'"

echo "Test completed successfully."