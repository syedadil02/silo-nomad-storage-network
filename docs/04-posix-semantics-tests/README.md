# Sub-Task 4: POSIX Semantics Torture Tests & Multi-Writer Concurrency (DEV-936)

## Goal

Subject the Silo CSI-S3 storage integration to an exhaustive POSIX filesystem torture test suite and a multi-node concurrent writer stress test across two distinct Nomad client nodes. Characterize which POSIX filesystem contracts hold up under `s3fs` userspace emulation and uncover failure modes under concurrent distributed write patterns.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **CSI Plugin Image:** `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Worker Test Image:** `docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e`
* **Silo Backend Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Cluster Topology:** 1 Server + 2 Clients (`nomad-client-1`, `nomad-client-2`) on same physical host
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Active Nomad cluster with healthy `silo-s3-csi` controller and node daemons.
* Multi-writer CSI volume `silo-vol-multi` registered with `access_mode = "multi-node-multi-writer"`.
* POSIX torture test runner [`scripts/posix-test-suite.sh`](file:///var/home/syedadil/personal/silo-nomad-storage-network/scripts/posix-test-suite.sh).

---

## Step-by-Step Procedure & Verification

### Step 1: Execute POSIX Torture Test Suite (Tests 1 through 5)
* **Command:**
  ```bash
  ./scripts/posix-test-suite.sh
  ```
* **Expected Result:**
  * Test 1 (Renames): Simple, overwrite, and directory renames succeed.
  * Test 2 (In-place Appends): 50 sequential appends preserved.
  * Test 3 (Sparse Files): 10MB sparse file created; verify block usage.
  * Test 4 (Links): Test symlink and hardlink creation.
  * Test 5 (Directory Scale): Rapid creation and listing of 200 small files.
* **Actual Result:** **PASS (with Behavioral Gaps)**.
  * Renames: PASS. Handled via S3 `CopyObject` + `DeleteObject`.
  * Appends: PASS. Single-writer preserved 50/50 lines.
  * Sparse Files: BEHAVIORAL GAP. Zero-filled 10MiB (`du -k` = 10,241 KiB, 20,481 blocks); S3 cannot represent filesystem holes.
  * Links: Symlinks PASS (`x-amz-meta-mode`). Hardlinks FAIL (`ln: Not supported`, `ENOTSUP`) due to lack of inode tables.
  * Directory Scale: PASS. 200 files touched in 2s, listed in 0.02s.
* **Evidence:** Captured in [`evidence/posix-suite-run.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/04-posix-semantics-tests/evidence/posix-suite-run.txt).

### Step 2: Deploy Multi-Node Concurrent Writer Job (Test 6)
* **Command:**
  ```bash
  nomad volume create nomad/volumes/vol-multi-writer.hcl
  nomad job run nomad/jobs/consumer-multi-writer.nomad
  nomad job status consumer-multi-writer
  ```
* **Expected Result:** Job schedules `count = 2` workers onto distinct hosts (`nomad-client-1` and `nomad-client-2`). Both workers concurrently append 50 timestamped lines each to `/data/concurrent-append.log`.
* **Actual Result:** **PASS (Placement & Execution)**. Worker 1 placed on `nomad-client-1` (`432b3e46`), Worker 2 placed on `nomad-client-2` (`adf6f0bf`). Both completed 50 append cycles.
* **Evidence:** Captured in [`evidence/multi-writer-alloc-status.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/04-posix-semantics-tests/evidence/multi-writer-alloc-status.txt) and [`evidence/multi-writer-worker-logs.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/04-posix-semantics-tests/evidence/multi-writer-worker-logs.txt).

### Step 3: Inspect S3 Backend for Multi-Node Concurrency Corruption
* **Command:**
  ```bash
  mc cat local/nomad-tests/vol-multi-writer/concurrent-append.log | cat -v | head -n 35
  ```
* **Expected Result:** 100 interleaved atomic log lines.
* **Actual Result:** **FAIL (CRITICAL CORRUPTION)**.
  * Resulting object exhibits **53 lost updates**.
  * File is heavily corrupted with binary null bytes (`^@^@^@^@`) caused by independent client-side FUSE offset calculations.
* **Evidence:** Captured in [`evidence/multi-writer-lost-updates.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/04-posix-semantics-tests/evidence/multi-writer-lost-updates.txt) and [`evidence/multi-writer-bucket-ls.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/04-posix-semantics-tests/evidence/multi-writer-bucket-ls.txt).

---

## Results Table

| Test Scenario | POSIX Expectation | Silo CSI-S3 (`s3fs`) Result | Status | Workload Impact |
|---|---|---|:---:|---|
| **1. File & Dir Renames** | Atomic inode rename | Emulated via `CopyObject` + `DeleteObject` | **PASS** | Slow on large directory trees ($O(N)$ HTTP calls). |
| **2. Sequential Appends** | Atomic append at EOF | Buffered in FUSE cache; committed on close | **PASS** | Safe for single-writer workloads. |
| **3. Sparse File Handling** | Physical blocks = 0 | 10MB zero-filled (`du -k` = 10,241 KiB) | **BEHAVIORAL GAP** | Consumes full network bandwidth and object storage space. |
| **4. Symlinks** | Target path pointer | Emulated with `x-amz-meta-mode` header | **PASS** | Functional across client nodes. |
| **4. Hardlinks** | Inode link count increment | Fails immediately (`ENOTSUP`) | **RESTRICTION** | Git bare repos and hardlink caches fail. |
| **5. Directory Scaling** | Bulk file operations | 200 files touched in 2s, listed in 0.02s | **PASS** | Adequate for modest directory sizes. |
| **6. Multi-Node Concurrency** | 100 interleaved lines | 53 lost updates + binary null-byte holes (`^@`) | **CRITICAL FAILURE** | Fatal for shared logs, queues, and multi-writer files. |

---

## Findings & Problems Resolved

1. **Root Cause of Concurrency Corruption:** S3 lacks distributed byte-range locking. Client 1 and Client 2 maintain independent local page caches. When writing concurrently to the same object, whichever node flushes or closes last overwrites the S3 object entirely, clobbering the other node's updates and injecting null-byte offset padding (`\x00`).
2. **Sparse File Materialization:** S3 cannot store filesystem holes. Preallocated database tables or virtual disk files immediately consume full network bandwidth and backend disk capacity.
3. **Hardlink Incompatibility:** Without POSIX inode link count tracking, hardlinks cannot function on S3 object storage.

---

## Conclusion

Silo CSI-S3 storage is **safe** for single-writer workloads, read-heavy media distribution, and static asset caching. However, it is **strictly unsafe and fatal** for concurrent multi-writer shared files and transactional ACID databases (SQLite, PostgreSQL, MySQL) that depend on byte-range locking and atomic fsync semantics.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Run the single-node POSIX torture test suite
./scripts/posix-test-suite.sh

# 2. Deploy multi-node concurrent writer job
nomad volume create nomad/volumes/vol-multi-writer.hcl
nomad job run nomad/jobs/consumer-multi-writer.nomad

# 3. Inspect the resulting S3 object in Silo
mc cat local/nomad-tests/vol-multi-writer/concurrent-append.log | cat -v | head -n 35
```

### Clean Up
```bash
nomad job stop -purge consumer-multi-writer
nomad volume deregister silo-vol-multi
```
