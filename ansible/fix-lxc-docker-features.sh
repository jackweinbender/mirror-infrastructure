#!/bin/bash
# Enable Docker-required LXC features on a Proxmox container
# Usage: ./fix-lxc-docker-features.sh <ctid> [pve-host]
# Example: ./fix-lxc-docker-features.sh 134 caba-host

if [ $# -lt 1 ]; then
    echo "Usage: $0 <container-id> [pve-host]"
    echo ""
    echo "Examples:"
    echo "  $0 134                    # Requires 'pct set' available in PATH"
    echo "  $0 134 caba-host          # Run via ssh on caba-host"
    exit 1
fi

CTID=$1
PVE_HOST=${2:-localhost}

echo "═══════════════════════════════════════════════════════"
echo "Enabling Docker features for LXC container $CTID"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check if running remotely
if [ "$PVE_HOST" != "localhost" ] && [ "$PVE_HOST" != "127.0.0.1" ]; then
    echo "🔧 Configuring via SSH to $PVE_HOST..."
    ssh "root@$PVE_HOST" << EOF
        echo "1️⃣  Stopping container $CTID..."
        pct stop $CTID || true
        sleep 2
        
        echo "2️⃣  Setting Docker features (nesting=1, keyctl=1)..."
        pct set $CTID --features nesting=1,keyctl=1
        
        echo "3️⃣  Rebooting container $CTID..."
        pct start $CTID
        sleep 3
        
        echo ""
        echo "✅ Container configured! Current features:"
        pct config $CTID | grep features
EOF
    EXIT_CODE=$?
else
    echo "🔧 Configuring locally (requires root/sudo)..."
    
    # Check if running as root
    if [ "$(id -u)" != "0" ]; then
        echo "❌ This script requires root access"
        echo "   Re-run with: sudo $0 $CTID"
        exit 1
    fi
    
    echo "1️⃣  Stopping container $CTID..."
    pct stop $CTID || true
    sleep 2
    
    echo "2️⃣  Setting Docker features (nesting=1, keyctl=1)..."
    pct set $CTID --features nesting=1,keyctl=1
    
    echo "3️⃣  Rebooting container $CTID..."
    pct start $CTID
    sleep 3
    
    echo ""
    echo "✅ Container configured! Current features:"
    pct config $CTID | grep features
    EXIT_CODE=$?
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "✅ Configuration complete!"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo "1. Wait a few seconds for the container to boot"
    echo "2. Re-run your playbook against the container:"
    echo ""
    echo "   ansible-playbook playbooks/local-lxc-add-docker.yaml -e lxc_target=lxc-134"
    echo ""
else
    echo ""
    echo "❌ Configuration failed!"
    echo "   Check that the container ID is correct: pct list"
    exit 1
fi
