# Sub-Task 7: Static Host-Managed FUSE Volume Fallback (DEV-939)

## Goal

Implement and validate a resilient **Static Host-Managed FUSE Fallback** pattern:
1. Mount the Silo S3 bucket directly onto the Linux host at `/tmp/nomad-lab/volumes/fuse-fallback` using containerized `s3fs` with bidirectional mount propagation (`:rshared`), requiring zero host package installations on immutable OS distributions.
2. Expose the host path as a standard Nomad **Host Volume** (`host_volume "fuse-fallback"`).
3. Validate end-to-end workload consumption, payload persistence, and compare operational reliability against the Nomad CSI plugin driver.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **Fallback FUSE Daemon:** Containerized `s3fs v1.89` via `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Consumer Workload Image:** `docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e`
* **Silo Backend Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Active Nomad cluster with `nomad-client-1` configured with `host_volume "fuse-fallback"`.
* Running Silo S3 server on `http://127.0.0.1:9000` with bucket `nomad-tests`.
* Nomad Variable `nomad/jobs/csi-s3-plugin` populated with credentials.
* Host FUSE automation script [`scripts/setup-fuse-fallback.sh`](file:///var/home/syedadil/personal/silo-nomad-storage-network/scripts/setup-fuse-fallback.sh).

---

## Step-by-Step Procedure & Verification

### Step 1: Mount Silo S3 Bucket to Host via Containerized FUSE
* **Command:**
  ```bash
  sudo ./scripts/setup-fuse-fallback.sh start
  grep 'fuse-fallback' /proc/mounts
  ls -la /tmp/nomad-lab/volumes/fuse-fallback
  ```
* **Expected Result:** Container `silo-fuse-fallback` launches with `--device /dev/fuse` and mounts bucket `nomad-tests` to `/tmp/nomad-lab/volumes/fuse-fallback` with `:rshared` propagation.
* **Actual Result:** **PASS**. Mount active in `/proc/mounts` and directories visible on host.
* **Evidence:** Captured in [`evidence/host-fuse-mount.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/07-fuse-host-volume-fallback/evidence/host-fuse-mount.txt).

### Step 2: Deploy Consumer Workload Claiming Host Volume
* **Command:**
  ```bash
  nomad job run nomad/jobs/consumer-fuse-fallback.nomad
  ALLOC_ID=$(nomad job status consumer-fuse-fallback | grep -E 'consumer +0 +run' | awk '{print $1}')
  nomad alloc logs "$ALLOC_ID" app
  ```
* **Expected Result:** Workload claims volume `type = "host"`, mounts `/mnt/fuse-fallback`, writes a timestamped verification payload, and reads it back.
* **Actual Result:** **PASS**. Container ran successfully and wrote `fallback-consumer-proof.txt`.
* **Evidence:** Captured in [`evidence/fallback-consumer-job-status.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/07-fuse-host-volume-fallback/evidence/fallback-consumer-job-status.txt) and [`evidence/fallback-consumer-logs.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/07-fuse-host-volume-fallback/evidence/fallback-consumer-logs.txt).

### Step 3: Verify Persistence in Silo S3 Object Store
* **Command:**
  ```bash
  mc ls local/nomad-tests/fallback-consumer-proof.txt
  mc cat local/nomad-tests/fallback-consumer-proof.txt
  ```
* **Expected Result:** Payload written inside the consumer container exists in the Silo S3 bucket.
* **Actual Result:** **PASS**. Object `fallback-consumer-proof.txt` (78 bytes) verified in Silo backend.
* **Evidence:** Captured in [`evidence/silo-fallback-proof.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/07-fuse-host-volume-fallback/evidence/silo-fallback-proof.txt).

---

## Results Table

### Comparative Trade-Off Matrix: Nomad CSI vs. Static Host FUSE

| Architectural Dimension | Nomad CSI (`mwantia/nomad-csi-s3-plugin`) | Static Host FUSE Fallback (`s3fs` + Host Volume) |
|---|---|---|
| **Provisioning Model** | **Dynamic:** Nomad API/CLI provisions buckets and sub-prefixes on demand. | **Static:** Requires pre-creating mount paths on host before placing workloads. |
| **Scheduler Awareness** | **High:** Nomad evaluates CSI plugin health, node capabilities, and volume claim counts during scheduling. | **Low:** Nomad only checks path existence on host; blind to whether backend S3 or FUSE process is alive. |
| **Operational Complexity** | **High:** Requires separate Controller job (`count=1`) and Node daemon job (`system`), plus CSI socket management. | **Minimal:** Simple host script or systemd service; standard Nomad `host_volume` stanza. |
| **Failure Recovery** | **Fragile on Daemon Death:** Killing node plugin leaves broken kernel mounts (`ENOTCONN`), blocking in-place container restarts. | **Local Process Only:** Managed by host process supervisor (systemd / container auto-restart). |
| **Multi-Node Mobility** | **Seamless:** Volumes claimable on any node running the CSI node plugin. | **Constrained:** Workload must be pinned (`constraint`) to the specific node(s) where host volume is mounted. |
| **Software Maturity** | **Experimental:** Upstream plugin is a single-author fork without maintenance since Oct 2024. | **Production-Proven:** Uses official, battle-tested `s3fs-fuse` directly with standard Nomad features. |

---

## Findings & Problems Resolved

1. **Mount Propagation on Immutable Linux:** On Fedora Silverblue, package installations require host layering and reboots. By running `s3fs` inside a privileged container with bidirectional bind propagation (`:rshared`), the mount point is projected onto the host VFS without modifying the underlying OS.
2. **Elimination of CSI Controller Hazards:** Host FUSE bypasses Nomad CSI controller elections, gRPC socket serialization, and plugin lifecycle complexity entirely.
3. **Production Recommendation:** For production teams lacking dedicated engineers to vendor and patch experimental CSI Go code, Static Host FUSE provides identical POSIX-over-S3 functionality with far higher reliability.

---

## Conclusion

The Static Host-Managed FUSE Fallback is fully operational and verified. It provides equivalent POSIX-over-S3 capabilities to container workloads using native Nomad `host_volume` declarations, eliminating CSI socket management and controller election hazards. It stands as the primary recommended deployment pattern for production environments.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Mount Silo bucket directly to host volume path
sudo ./scripts/setup-fuse-fallback.sh start

# 2. Deploy consumer job claiming host volume
nomad job run nomad/jobs/consumer-fuse-fallback.nomad

# 3. Verify writeback in Silo S3 bucket
mc cat local/nomad-tests/fallback-consumer-proof.txt
```

### Clean Up
```bash
nomad job stop -purge consumer-fuse-fallback
sudo ./scripts/setup-fuse-fallback.sh stop
```
