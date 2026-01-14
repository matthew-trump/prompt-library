#!/bin/bash

# Harden new Debian 12 Linode server (idempotent - safe to run multiple times)
# Usage: LINODE_IP=xxx.xxx.xxx.xxx LINODE_ROOT_PASSWORD=yourpassword LINODE_USER=yourname SSH_PUBLIC_KEY_PATH=~/.ssh/id_rsa.pub ./harden-linode.sh
# Optional: SSH_PRIVATE_KEY_PATH (defaults to SSH_PUBLIC_KEY_PATH without .pub)

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

if [ -z "$LINODE_USER" ]; then
    echo "Error: LINODE_USER environment variable not set (your non-root username)"
    exit 1
fi

if [ -z "$SSH_PUBLIC_KEY_PATH" ]; then
    echo "Error: SSH_PUBLIC_KEY_PATH environment variable not set (path to your public key)"
    exit 1
fi

# Expand tilde in public key path
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"

# Verify public key file exists
if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
    echo "Error: SSH public key file not found at $SSH_PUBLIC_KEY_PATH"
    exit 1
fi

# Determine private key path (default to public key path without .pub)
if [ -z "$SSH_PRIVATE_KEY_PATH" ]; then
    SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"
fi

# Expand tilde in private key path
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

# Verify private key file exists
if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
    echo "Error: SSH private key file not found at $SSH_PRIVATE_KEY_PATH"
    exit 1
fi

echo "========================================="
echo "Hardening Debian 12 server at $LINODE_IP"
echo "Creating user: $LINODE_USER"
echo "Using SSH public key: $SSH_PUBLIC_KEY_PATH"
echo "Using SSH private key: $SSH_PRIVATE_KEY_PATH"
echo "========================================="

# Function to run commands via SSH as root (before hardening)
run_remote_root() {
    sshpass -p "$LINODE_ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$LINODE_IP "$1"
}

# Function to run commands via SSH as user with sudo (after hardening)
run_remote_user() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "sudo bash -c '$1'"
}

# Function to check if command succeeds as root (returns 0 on success, 1 on failure)
check_remote_root() {
    sshpass -p "$LINODE_ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$LINODE_IP "$1" &>/dev/null
    return $?
}

# Function to check if command succeeds as user (returns 0 on success, 1 on failure)
check_remote_user() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "sudo bash -c '$1'" &>/dev/null
    return $?
}

# Determine if root login is still enabled
ROOT_LOGIN_ENABLED=false
if sshpass -p "$LINODE_ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$LINODE_IP "echo ok" &>/dev/null; then
    ROOT_LOGIN_ENABLED=true
    echo "  → Root login detected as enabled"
else
    echo "  → Root login detected as disabled, using $LINODE_USER with sudo"
fi

# Choose which functions to use based on root login status
if [ "$ROOT_LOGIN_ENABLED" = true ]; then
    run_remote() { run_remote_root "$1"; }
    check_remote() { check_remote_root "$1"; }
else
    run_remote() { run_remote_user "$1"; }
    check_remote() { check_remote_user "$1"; }
fi

# Step 1: Update system packages
echo ""
echo "[1/9] Updating system packages..."
run_remote "apt update && apt upgrade -y"

# Step 2: Create non-root user with sudo privileges (if doesn't exist)
echo ""
echo "[2/9] Creating user $LINODE_USER with sudo privileges..."
if check_remote "id -u $LINODE_USER"; then
    echo "  ✓ User $LINODE_USER already exists, skipping creation"
else
    run_remote "useradd -m -s /bin/bash $LINODE_USER"
    echo "  ✓ User $LINODE_USER created"
fi

# Ensure user is in sudo group
if check_remote "groups $LINODE_USER | grep -q sudo"; then
    echo "  ✓ User $LINODE_USER already in sudo group"
else
    run_remote "usermod -aG sudo $LINODE_USER"
    echo "  ✓ User $LINODE_USER added to sudo group"
fi

# Step 3: Enable passwordless sudo
echo ""
echo "[3/9] Enabling passwordless sudo for $LINODE_USER..."
if check_remote "test -f /etc/sudoers.d/$LINODE_USER"; then
    echo "  ✓ Passwordless sudo already configured"
else
    run_remote "echo '$LINODE_USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$LINODE_USER && chmod 440 /etc/sudoers.d/$LINODE_USER"
    echo "  ✓ Passwordless sudo configured"
fi

# Step 4: Create SSH directory for new user
echo ""
echo "[4/9] Setting up SSH directory for $LINODE_USER..."
if check_remote "test -d /home/$LINODE_USER/.ssh"; then
    echo "  ✓ SSH directory already exists"
else
    run_remote "mkdir -p /home/$LINODE_USER/.ssh && chmod 700 /home/$LINODE_USER/.ssh && chown $LINODE_USER:$LINODE_USER /home/$LINODE_USER/.ssh"
    echo "  ✓ SSH directory created"
fi

# Step 5: Copy SSH public key to server
echo ""
echo "[5/9] Copying SSH public key to server..."
# Always copy/update the key to ensure it's current
if [ "$ROOT_LOGIN_ENABLED" = true ]; then
    sshpass -p "$LINODE_ROOT_PASSWORD" scp -o StrictHostKeyChecking=no "$SSH_PUBLIC_KEY_PATH" root@$LINODE_IP:/home/$LINODE_USER/.ssh/authorized_keys
    run_remote "chmod 600 /home/$LINODE_USER/.ssh/authorized_keys && chown $LINODE_USER:$LINODE_USER /home/$LINODE_USER/.ssh/authorized_keys"
else
    scp -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" "$SSH_PUBLIC_KEY_PATH" $LINODE_USER@$LINODE_IP:/home/$LINODE_USER/.ssh/authorized_keys.tmp
    run_remote "mv /home/$LINODE_USER/.ssh/authorized_keys.tmp /home/$LINODE_USER/.ssh/authorized_keys && chmod 600 /home/$LINODE_USER/.ssh/authorized_keys && chown $LINODE_USER:$LINODE_USER /home/$LINODE_USER/.ssh/authorized_keys"
fi
echo "  ✓ SSH public key copied and permissions set"

# Step 6: Test that new user can SSH with keys
echo ""
echo "[6/9] Testing SSH connection as $LINODE_USER with private key..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "echo 'SSH key authentication working for $LINODE_USER'"

# Step 7: Disable root login and password authentication
echo ""
echo "[7/9] Disabling root SSH login and password authentication..."

# Only proceed if root login is still enabled
if [ "$ROOT_LOGIN_ENABLED" = false ]; then
    echo "  ✓ SSH hardening already configured (root login disabled)"
else
    # Update SSH config
    run_remote "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    
    # Restart sshd - this will likely kill the current connection
    echo "  → Restarting sshd (connection may drop)..."
    run_remote "systemctl restart sshd" || true  # Ignore connection drop error
    
    # Wait for sshd to come back up
    echo "  → Waiting for sshd to restart..."
    sleep 5
    
    # Verify we can connect as the new user
    echo "  → Testing connection as $LINODE_USER..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "echo 'Connection successful'" &>/dev/null; then
        echo "  ✓ SSH hardening configured and verified"
        
        # Switch to user-based commands
        ROOT_LOGIN_ENABLED=false
        run_remote() { run_remote_user "$1"; }
        check_remote() { check_remote_user "$1"; }
    else
        echo "  ✗ ERROR: Cannot connect as $LINODE_USER after hardening!"
        echo "  You may need to manually fix SSH configuration on the server"
        exit 1
    fi
fi

# Step 8: Install and configure UFW firewall
echo ""
echo "[8/9] Installing and configuring UFW firewall..."
if check_remote "which ufw"; then
    echo "  ✓ UFW already installed"
else
    run_remote "apt install -y ufw"
    echo "  ✓ UFW installed"
fi

if check_remote "ufw status | grep -q 'Status: active'"; then
    echo "  ✓ UFW already active"
else
    run_remote "ufw --force reset && ufw default deny incoming && ufw default allow outgoing && ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable"
    echo "  ✓ UFW configured and enabled"
fi

# Step 9: Install fail2ban
echo ""
echo "[9/9] Installing fail2ban..."
if check_remote "which fail2ban-client"; then
    echo "  ✓ fail2ban already installed"
    if check_remote "systemctl is-active --quiet fail2ban"; then
        echo "  ✓ fail2ban already running"
    else
        run_remote "systemctl enable fail2ban && systemctl start fail2ban"
        echo "  ✓ fail2ban enabled and started"
    fi
else
    run_remote "apt install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban"
    echo "  ✓ fail2ban installed and started"
fi

echo ""
echo "========================================="
echo "✓ Hardening complete!"
echo "========================================="
echo ""
echo "Your server is now hardened with:"
echo "  • Non-root user: $LINODE_USER (with passwordless sudo)"
echo "  • SSH key authentication only"
echo "  • Root login disabled"
echo "  • UFW firewall active (ports 22, 80, 443 open)"
echo "  • fail2ban protecting against brute force"
echo ""
echo "Next steps:"
echo "  1. Test login: ssh -i $SSH_PRIVATE_KEY_PATH $LINODE_USER@$LINODE_IP"
echo "  2. Verify sudo: ssh -i $SSH_PRIVATE_KEY_PATH $LINODE_USER@$LINODE_IP 'sudo whoami'"
echo ""
echo "⚠️  Root password login is now DISABLED"
echo "⚠️  Keep your SSH private key safe!"
echo ""