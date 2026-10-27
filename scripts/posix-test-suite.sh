#!/usr/bin/env bash
# ==============================================================================
# scripts/posix-test-suite.sh
# Comprehensive POSIX semantics torture tests for Nomad CSI-S3 volumes
# ==============================================================================
set -euo pipefail

TARGET_DIR="${1:-}"

if [ -z "$TARGET_DIR" ]; then
  ALLOC_ID=$(nomad job status consumer-single-writer 2>/dev/null | grep -E 'writer +0 +run +running' | awk '{print $1}' || true)
  if [ -z "$ALLOC_ID" ]; then
    echo "Error: No target directory provided and no running consumer-single-writer allocation found." >&2
    echo "Usage: $0 [/path/to/mount/dir] OR run with active consumer-single-writer job." >&2
    exit 1
  fi
  echo "Targeting active Nomad allocation: ${ALLOC_ID}"
  RUN_SH="nomad alloc exec -i ${ALLOC_ID} sh"
  TEST_DIR="/data/posix-suite"
else
  RUN_SH="sh"
  TEST_DIR="${TARGET_DIR}/posix-suite"
fi

$RUN_SH <<EOF
set -eu
TEST_DIR="${TEST_DIR}"

echo "======================================================================"
echo "          NOMAD SILO CSI-S3 POSIX SEMANTICS TORTURE SUITE             "
echo "======================================================================"
echo "Running tests in: \${TEST_DIR}"

rm -rf "\${TEST_DIR}" && mkdir -p "\${TEST_DIR}"

echo ""
echo "--- TEST 1: File & Directory Renames ---"
echo "rename-v1" > "\${TEST_DIR}/file-a.txt"
mv "\${TEST_DIR}/file-a.txt" "\${TEST_DIR}/file-b.txt"
if [ -f "\${TEST_DIR}/file-b.txt" ] && [ ! -f "\${TEST_DIR}/file-a.txt" ]; then
  echo "  [PASS] Simple file rename (file-a -> file-b)"
else
  echo "  [FAIL] Simple file rename failed"
fi

echo "rename-v2" > "\${TEST_DIR}/file-c.txt"
mv -f "\${TEST_DIR}/file-c.txt" "\${TEST_DIR}/file-b.txt"
CONTENT=\$(cat "\${TEST_DIR}/file-b.txt")
if [ "\$CONTENT" = "rename-v2" ] && [ ! -f "\${TEST_DIR}/file-c.txt" ]; then
  echo "  [PASS] Overwrite rename (file-c -> file-b)"
else
  echo "  [FAIL] Overwrite rename failed"
fi

mkdir -p "\${TEST_DIR}/sub-v1"
echo "nested-data" > "\${TEST_DIR}/sub-v1/nested.txt"
mv "\${TEST_DIR}/sub-v1" "\${TEST_DIR}/sub-v2"
if [ -f "\${TEST_DIR}/sub-v2/nested.txt" ] && [ ! -d "\${TEST_DIR}/sub-v1" ]; then
  echo "  [PASS] Directory rename with contents (sub-v1 -> sub-v2)"
else
  echo "  [FAIL] Directory rename failed"
fi

echo ""
echo "--- TEST 2: Sequential In-place Appends ---"
rm -f "\${TEST_DIR}/append.txt"
for i in \$(seq 1 50); do
  echo "append-line-\$i" >> "\${TEST_DIR}/append.txt"
done
LINES=\$(wc -l < "\${TEST_DIR}/append.txt")
if [ "\$LINES" -eq 50 ]; then
  echo "  [PASS] Sequential appends (50/50 lines preserved)"
else
  echo "  [FAIL] Sequential appends lost data (\$LINES/50 lines)"
fi

echo ""
echo "--- TEST 3: Sparse File Handling (stat vs du) ---"
truncate -s 10M "\${TEST_DIR}/sparse.bin"
STAT_BYTES=\$(stat -c '%s' "\${TEST_DIR}/sparse.bin")
STAT_BLOCKS=\$(stat -c '%b' "\${TEST_DIR}/sparse.bin")
DU_KB=\$(du -k "\${TEST_DIR}/sparse.bin" | awk '{print \$1}')
echo "  Logical file size (stat -c '%s'): \${STAT_BYTES} bytes"
echo "  Allocated disk blocks (stat -c '%b'): \${STAT_BLOCKS}"
echo "  Reported disk usage (du -k): \${DU_KB} KiB"
if [ "\$DU_KB" -gt 5000 ]; then
  echo "  [BEHAVIORAL NOTE] S3 does not support sparse holes: file zero-filled on object upload."
else
  echo "  [PASS] Sparse holes preserved."
fi

echo ""
echo "--- TEST 4: Link Semantics (Hardlinks vs Symlinks) ---"
echo "target-payload" > "\${TEST_DIR}/target.txt"
ln -s "\${TEST_DIR}/target.txt" "\${TEST_DIR}/symlink.txt"
if [ -L "\${TEST_DIR}/symlink.txt" ] && [ "\$(cat "\${TEST_DIR}/symlink.txt")" = "target-payload" ]; then
  echo "  [PASS] Symlink creation and resolution supported"
else
  echo "  [FAIL] Symlink failed"
fi

if ln "\${TEST_DIR}/target.txt" "\${TEST_DIR}/hardlink.txt" 2>"\${TEST_DIR}/hardlink.err"; then
  echo "  [PASS] Hardlink supported"
else
  ERR=\$(cat "\${TEST_DIR}/hardlink.err" 2>/dev/null || true)
  echo "  [EXPECTED RESTRICTION] Hardlink failed as expected for object storage: \${ERR}"
fi

echo ""
echo "--- TEST 5: Directory Scale (200 Files Benchmark) ---"
mkdir -p "\${TEST_DIR}/scale"
T1=\$(date +%s)
for i in \$(seq 1 200); do
  echo "payload-\$i" > "\${TEST_DIR}/scale/file_\$i.txt"
done
T2=\$(date +%s)
FILE_COUNT=\$(ls -1 "\${TEST_DIR}/scale" | wc -l)
ls -la "\${TEST_DIR}/scale" > /dev/null
T3=\$(date +%s)
rm -rf "\${TEST_DIR}/scale"
T4=\$(date +%s)

echo "  Files created: \${FILE_COUNT} / 200"
echo "  Touch elapsed: \$(( T2 - T1 ))s"
echo "  Directory list elapsed: \$(( T3 - T2 ))s"
echo "  Directory cleanup elapsed: \$(( T4 - T3 ))s"
if [ "\$FILE_COUNT" -eq 200 ]; then
  echo "  [PASS] Directory scaling test passed."
else
  echo "  [FAIL] Directory scale file count mismatch."
fi

rm -rf "\${TEST_DIR}"
echo ""
echo "======================================================================"
echo "                 POSIX TORTURE SUITE FINISHED                         "
echo "======================================================================"
EOF
