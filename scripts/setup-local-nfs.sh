#!/usr/bin/env bash
# ==============================================================================
# scripts/setup-local-nfs.sh
# Sets up loopback NFS export on Linux for Nomad benchmark baseline
# ==============================================================================
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Error: Run with 'sudo ./scripts/setup-local-nfs.sh'." >&2
  exit 1
fi

EXPORT_DIR="/tmp/nomad-lab/nfs-export"
MOUNT_DIR="/tmp/nomad-lab/volumes/nfs-mount"
EXPORTS_FILE="/etc/exports.d/nomad-lab.exports"

echo "Setting up local loopback NFS baseline..."
mkdir -p "$EXPORT_DIR" "$MOUNT_DIR" /etc/exports.d
chmod 777 "$EXPORT_DIR" "$MOUNT_DIR"

# Configure NFS export without fsid=0 to support both NFSv3 and NFSv4
echo "${EXPORT_DIR} 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" > "$EXPORTS_FILE"

# Start service and reload export table
systemctl start nfs-server
exportfs -rav

# Mount if not already mounted
if ! grep -qs "${MOUNT_DIR}" /proc/mounts; then
  echo "Mounting 127.0.0.1:${EXPORT_DIR} to ${MOUNT_DIR}..."
  mount -t nfs 127.0.0.1:"${EXPORT_DIR}" "${MOUNT_DIR}"
fi

# Ensure SELinux and permissions
chcon -Rt container_file_t "$MOUNT_DIR" "$EXPORT_DIR" 2>/dev/null || true
chmod 777 "$MOUNT_DIR" "$EXPORT_DIR"

echo "Loopback NFS export and mount established successfully:"
df -hT "$MOUNT_DIR"
