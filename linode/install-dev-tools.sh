#!/bin/bash

# Install development tools on Debian 12 server
# Installs: git, Node.js (LTS), npm, Python, venv, build-essential, and other common dev tools
# Usage: LINODE_IP=xxx.xxx.xxx.xxx LINODE_USER=yourname SSH_PRIVATE_KEY_PATH=~/.ssh/key ./install-dev-tools.sh

set -e

# Check required environment variables
if [ -z "$LINODE_IP" ]; then
    echo "Error: LINODE_IP environment variable not set"
    exit 1
fi

if [ -z "$LINODE_USER" ]; then
    echo "Error: LINODE_USER environment variable not set"
    exit 1
fi

if [ -z "$SSH_PRIVATE_KEY_PATH" ]; then
    echo "Error: SSH_PRIVATE_KEY_PATH environment variable not set"
    exit 1
fi

# Expand tilde in private key path
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

# Verify private key exists
if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
    echo "Error: SSH private key not found at $SSH_PRIVATE_KEY_PATH"
    exit 1
fi

# Node.js version to install (LTS)
NODE_MAJOR=${NODE_MAJOR:-20}

echo "========================================="
echo "Installing Development Tools"
echo "Server: $LINODE_IP"
echo "User: $LINODE_USER"
echo "Node.js: v$NODE_MAJOR.x (LTS)"
echo "Python: 3.x with venv"
echo "========================================="

# Function to run remote commands
run_remote() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "sudo bash -c '$1'"
}

# Function to check if command succeeds
check_remote() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "sudo bash -c '$1'" &>/dev/null
    return $?
}

# Step 1: Update package lists
echo ""
echo "[1/8] Updating package lists..."
run_remote "apt update"
echo "  ✓ Package lists updated"

# Step 2: Install git
echo ""
echo "[2/8] Installing git..."
if check_remote "which git"; then
    CURRENT_GIT=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "git --version")
    echo "  ✓ git already installed ($CURRENT_GIT)"
else
    run_remote "apt install -y git"
    NEW_GIT=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "git --version")
    echo "  ✓ git installed ($NEW_GIT)"
fi

# Step 3: Install Python and venv
echo ""
echo "[3/8] Installing Python and venv..."
if check_remote "which python3"; then
    CURRENT_PYTHON=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "python3 --version")
    echo "  ✓ Python already installed ($CURRENT_PYTHON)"
else
    run_remote "apt install -y python3"
    NEW_PYTHON=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "python3 --version")
    echo "  ✓ Python installed ($NEW_PYTHON)"
fi

# Install python3-venv
if check_remote "dpkg -l | grep -q python3-venv"; then
    echo "  ✓ python3-venv already installed"
else
    run_remote "apt install -y python3-venv"
    echo "  ✓ python3-venv installed"
fi

# Install pip
if check_remote "which pip3"; then
    CURRENT_PIP=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "pip3 --version")
    echo "  ✓ pip already installed ($CURRENT_PIP)"
else
    run_remote "apt install -y python3-pip"
    NEW_PIP=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "pip3 --version")
    echo "  ✓ pip installed ($NEW_PIP)"
fi

# Step 4: Install build-essential and common build tools
echo ""
echo "[4/8] Installing build tools..."
if check_remote "dpkg -l | grep -q build-essential"; then
    echo "  ✓ build-essential already installed"
else
    run_remote "apt install -y build-essential"
    echo "  ✓ build-essential installed"
fi

# Additional useful build tools
BUILD_TOOLS="curl wget ca-certificates gnupg"
for tool in $BUILD_TOOLS; do
    if check_remote "which $tool"; then
        echo "  ✓ $tool already installed"
    else
        run_remote "apt install -y $tool"
        echo "  ✓ $tool installed"
    fi
done

# Step 5: Install Node.js and npm
echo ""
echo "[5/8] Installing Node.js v$NODE_MAJOR.x..."

# Check if Node.js is already installed with correct version
if check_remote "which node"; then
    CURRENT_NODE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "node --version")
    CURRENT_MAJOR=$(echo $CURRENT_NODE | cut -d'.' -f1 | sed 's/v//')
    
    if [ "$CURRENT_MAJOR" = "$NODE_MAJOR" ]; then
        echo "  ✓ Node.js already installed ($CURRENT_NODE)"
        SKIP_NODE=true
    else
        echo "  → Found Node.js $CURRENT_NODE, will upgrade to v$NODE_MAJOR.x"
        SKIP_NODE=false
    fi
else
    echo "  → Node.js not found, will install v$NODE_MAJOR.x"
    SKIP_NODE=false
fi

if [ "$SKIP_NODE" = false ]; then
    # Add NodeSource repository
    echo "  → Adding NodeSource repository..."
    run_remote "curl -fsSL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash -"
    
    # Install Node.js (includes npm)
    echo "  → Installing Node.js..."
    run_remote "apt install -y nodejs"
    
    NEW_NODE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "node --version")
    NEW_NPM=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "npm --version")
    echo "  ✓ Node.js installed ($NEW_NODE)"
    echo "  ✓ npm installed (v$NEW_NPM)"
fi

# Step 6: Verify npm and optionally update
echo ""
echo "[6/8] Checking npm..."
if check_remote "which npm"; then
    CURRENT_NPM=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "npm --version")
    echo "  ✓ npm installed (v$CURRENT_NPM)"
else
    echo "  ✗ npm not found (should have been installed with Node.js)"
    exit 1
fi

# Step 7: Install global npm packages (optional but useful)
echo ""
echo "[7/8] Installing useful global npm packages..."

GLOBAL_PACKAGES="yarn pnpm"
for package in $GLOBAL_PACKAGES; do
    if check_remote "npm list -g $package"; then
        echo "  ✓ $package already installed"
    else
        run_remote "npm install -g $package"
        echo "  ✓ $package installed globally"
    fi
done

# Step 8: Test Python venv creation
echo ""
echo "[8/8] Testing Python venv..."
if run_remote "cd /tmp && python3 -m venv test_venv && rm -rf test_venv"; then
    echo "  ✓ Python venv working correctly"
else
    echo "  ✗ Python venv test failed"
    exit 1
fi

echo ""
echo "========================================="
echo "✓ Development tools installation complete!"
echo "========================================="
echo ""

# Display versions
echo "Installed versions:"
GIT_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "git --version")
PYTHON_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "python3 --version")
PIP_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "pip3 --version | cut -d' ' -f2")
NODE_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "node --version")
NPM_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "npm --version")
YARN_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "yarn --version" 2>/dev/null || echo "not installed")
PNPM_VERSION=$(ssh -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" $LINODE_USER@$LINODE_IP "pnpm --version" 2>/dev/null || echo "not installed")

echo "  • $GIT_VERSION"
echo "  • $PYTHON_VERSION"
echo "  • pip v$PIP_VERSION"
echo "  • python3-venv (tested and working)"
echo "  • Node.js $NODE_VERSION"
echo "  • npm v$NPM_VERSION"
echo "  • yarn v$YARN_VERSION"
echo "  • pnpm v$PNPM_VERSION"
echo "  • build-essential (gcc, g++, make)"
echo ""
echo "Your server is now ready for:"
echo "  • Cloning git repositories"
echo "  • Building React/Vite applications"
echo "  • Running FastAPI applications with Python venv"
echo "  • Running npm/yarn/pnpm commands"
echo "  • Compiling native Node.js modules"
echo ""
echo "Example Python venv usage:"
echo "  python3 -m venv /path/to/venv"
echo "  source /path/to/venv/bin/activate"
echo "  pip install fastapi uvicorn"
echo ""