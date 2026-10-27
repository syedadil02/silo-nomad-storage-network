#!/usr/bin/env bash
# ==============================================================================
# scripts/setup-fuse-fallback.sh
# Mounts Silo S3 bucket directly to host volume path via containerized s3fs FUSE
# Bypasses Nomad CSI plugin layer for direct host-volume fallback
# ==============================================================================
set -euo pipefail

ACTION="${1:-start}"
MOUNT_DIR="/tmp/nomad-lab/volumes/fuse-fallback"
PASSWD_FILE="/tmp/nomad-lab/fuse-s3fs-passwd"
CONTAINER_NAME="silo-fuse-fallback"

if [ "${EUID}" -ne 0 ]; then
  echo "Error: Run with 'sudo ./scripts/setup-fuse-fallback.sh [start|stop]'." >&2
  exit 1
fi

if [ "$ACTION" = "stop" ]; then
  echo "Stopping Host FUSE Fallback..."
  podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
  umount -l "$MOUNT_DIR" 2>/dev/null || true
  rm -f "$PASSWD_FILE"
  echo "Host FUSE Fallback stopped successfully."
  exit 0
fi

echo "Setting up Static Host FUSE Fallback for Silo..."
podman rm -f "$CONTAINER_NAME" test-fuse-s3fs 2>/dev/null || true
umount -l "$MOUNT_DIR" 2>/dev/null || true
mkdir -p "$MOUNT_DIR"
chmod 777 "$MOUNT_DIR"

# 1. Fetch credentials dynamically from Nomad Variables
echo "Fetching credentials from Nomad Variables..."
NOMAD_VARS=$(/var/home/syedadil/.local/bin/nomad var get -out=json nomad/jobs/csi-s3-plugin 2>/dev/null || true)
if [ -z "$NOMAD_VARS" ]; then
  echo "Error: Could not retrieve nomad/jobs/csi-s3-plugin variable." >&2
  exit 1
fi

AK=$(echo "$NOMAD_VARS" | jq -r '.Items.access_key')
SK=$(echo "$NOMAD_VARS" | jq -r '.Items.secret_key')

echo "${AK}:${SK}" > "$PASSWD_FILE"
chmod 600 "$PASSWD_FILE"

# 2. Launch containerized s3fs with rshared mount propagation to host
echo "Launching containerized s3fs FUSE daemon..."
podman run -d --name "$CONTAINER_NAME" --replace \
  --privileged \
  --net=host \
  --device /dev/fuse \
  -v "${MOUNT_DIR}:/mnt/fuse-fallback:rshared" \
  -v "${PASSWD_FILE}:/etc/passwd-s3fs:ro" \
  --entrypoint s3fs \
  docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 \
  nomad-tests /mnt/fuse-fallback -f \
  -o url=http://127.0.0.1:9000 \
  -o passwd_file=/etc/passwd-s3fs \
  -o use_path_request_style \
  -o allow_other \
  -o mp_umask=000

# 3. Wait for FUSE mount to register
for i in $(seq 1 10); do
  if grep -qs "${MOUNT_DIR}" /proc/mounts; then
    break
  fi
  sleep 1
done

if ! grep -qs "${MOUNT_DIR}" /proc/mounts; then
  echo "Error: FUSE mount failed to appear in /proc/mounts." >&2
  podman logs "$CONTAINER_NAME"
  exit 1
fi

echo "Host FUSE mount established successfully at ${MOUNT_DIR}:"
ls -la "$MOUNT_DIR"
