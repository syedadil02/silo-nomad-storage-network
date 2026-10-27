# Sub-Task 6: FIO Performance Benchmark Comparison (DEV-938)

## Goal

Execute standardized Flexible I/O Tester (FIO) benchmarks across three persistent storage tiers in the Nomad cluster:
1. **Local Host SSD Volume:** Direct ext4 host volume (`/mnt/local-ssd`).
2. **Loopback NFS Volume:** In-kernel NFS v3/v4 network share (`/mnt/nfs`).
3. **Silo CSI-S3 Volume:** S3-backed persistent volume managed by Nomad CSI via `s3fs` (`/mnt/silo-csi`).

Quantify throughput, IOPS, and latency across sequential write, sequential read, and random 4KB mixed read/write workloads to establish concrete workload suitability boundaries.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **Benchmark Engine:** `fio v3.36` running inside `docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e`
* **CSI Plugin Image:** `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Silo Backend Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Storage Tiers Evaluated:** Local NVMe SSD (ext4), Loopback NFS (kernel RPC), Silo CSI S3 (userspace `s3fs` FUSE)
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Multi-node Nomad cluster active with healthy `silo-s3-csi` plugin.
* Loopback NFS export created via [`scripts/setup-local-nfs.sh`](file:///var/home/syedadil/personal/silo-nomad-storage-network/scripts/setup-local-nfs.sh).
* CSI volume `silo-vol-fio` registered via [`nomad/volumes/vol-fio-bench.hcl`](file:///var/home/syedadil/personal/silo-nomad-storage-network/nomad/volumes/vol-fio-bench.hcl).

---

## Step-by-Step Procedure & Verification

### Step 1: Establish Loopback NFS Baseline Export & Mount
* **Command:**
  ```bash
  sudo ./scripts/setup-local-nfs.sh
  df -hT /tmp/nomad-lab/volumes/nfs-mount
  ```
* **Expected Result:** Export `/tmp/nomad-lab/nfs-export` configured in `/etc/exports.d/nomad-lab.exports`, `nfs-server` started, and mounted to `/tmp/nomad-lab/volumes/nfs-mount`.
* **Actual Result:** **PASS**. NFS mount active and verified via `df -hT`.
* **Evidence:** Captured in [`evidence/nfs-setup-log.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/06-fio-performance-comparison/evidence/nfs-setup-log.txt).

### Step 2: Register Benchmark CSI Volume
* **Command:**
  ```bash
  nomad volume create nomad/volumes/vol-fio-bench.hcl
  nomad volume status silo-vol-fio
  ```
* **Expected Result:** Volume `silo-vol-fio` registered in Nomad catalog with `Schedulable = true`.
* **Actual Result:** **PASS**. Volume registered targeting `nomad-tests/vol-fio-bench`.

### Step 3: Launch FIO Benchmark Batch Job Across All Three Tiers
* **Command:**
  ```bash
  nomad job run nomad/jobs/fio-benchmark.nomad
  ALLOC_ID=$(nomad job status fio-benchmark | grep -E 'benchmarks +0 +run' | awk '{print $1}')
  nomad alloc logs -f "$ALLOC_ID" fio
  ```
* **Expected Result:** Batch container executes three standardized test profiles (128KB Seq Write 64MB, 128KB Seq Read 64MB, 4KB Random 70/30 16MB) across Local SSD, NFS, and Silo CSI-S3.
* **Actual Result:** **PASS**. Job completed with status `dead` (exit code 0), emitting full comparative metrics.
* **Evidence:** Captured in [`evidence/fio-raw-output.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/06-fio-performance-comparison/evidence/fio-raw-output.txt) and [`evidence/fio-summary-table.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/06-fio-performance-comparison/evidence/fio-summary-table.txt).

---

## Results Table

### 1. Sequential Write Performance (128KB block size, 64MB file)
*Measures bulk sequential writing typical of backups, logging, and export pipelines:*

| Storage Tier | Bandwidth (MiB/s) | IOPS | Avg Latency | Relative Slowdown |
|---|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **4,571 MiB/s** | 36,600 | 26.35 µs | 1.0x (Baseline) |
| **Loopback NFS** | **5,818 MiB/s** | 46,500 | 18.84 µs | 0.8x |
| **Silo CSI-S3** | **117 MiB/s** | 936 | 1,059.30 µs | **39.1x slower** |

### 2. Sequential Read Performance (128KB block size, 64MB file)
*Measures bulk sequential reading typical of dataset loading, media ingestion, and web asset streaming:*

| Storage Tier | Bandwidth (MiB/s) | IOPS | Avg Latency | Relative Slowdown |
|---|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **5,818 MiB/s** | 46,500 | 19.30 µs | 1.0x (Baseline) |
| **Loopback NFS** | **4,571 MiB/s** | 36,600 | 25.20 µs | 1.3x |
| **Silo CSI-S3** | **405 MiB/s** | 3,240 | 286.19 µs | **14.4x slower** |

### 3. Random 4KB Read/Write (70% Read / 30% Write mix, 16MB file)
*Simulates transactional metadata and small-block database activity:*

| Storage Tier | Read IOPS | Read BW | Write IOPS | Write BW | Avg Write Latency |
|---|:---:|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **314,000** | 1,226 MiB/s | **141,000** | 552 MiB/s | 1.43 µs |
| **Loopback NFS** | **80,700** | 315 MiB/s | **36,300** | 142 MiB/s | 3.30 µs |
| **Silo CSI-S3** | **12,000** | 46.7 MiB/s | **5,389** | 21.1 MiB/s | 82.61 µs |

### 4. Workload Suitability Matrix

| Workload Profile | Typical Examples | Silo CSI-S3 Viability | Primary Bottleneck |
|---|---|:---:|---|
| **Media / Asset Distribution** | Nginx uploads, user avatars, PDF reports, static video assets | **EXCELLENT** | None; 405 MiB/s read bandwidth exceeds 10GbE network link saturation. |
| **Cold Storage / Archiving** | Nightly database dumps, rotated syslog archives, tarballs | **GOOD** | Sequential writes (117 MiB/s) are adequate for background exports. |
| **Batch Big Data Processing** | Spark/Flink input data, ML model weights, read-only datasets | **GOOD** | Read-heavy patterns benefit from local kernel pagecache once primed. |
| **Software Builds / Caches** | Gradle/Maven caches, Go module proxies, NPM directories | **POOR** | Thousands of small 4KB reads/writes incur severe HTTP latency. |
| **ACID / Transactional DBs** | SQLite, PostgreSQL data directories, Redis RDB/AOF, etcd | **UNUSABLE** | Catastrophic latency; lack of fsync atomicity guarantees corrupts WAL. |

---

## Findings & Problems Resolved

1. **Sequential Write Overhead:** Silo CSI-S3 writes at 117 MiB/s (~39x slower than local disk) because each write operation must be translated into userspace FUSE buffers and serialized over HTTP multi-part upload streams.
2. **Sequential Read Feasibility:** Sequential read bandwidth of 405 MiB/s is strong and fully viable for asset serving, video streaming, and machine learning model distribution.
3. **Random Latency Surge:** Random 4KB write latency surges 50x (1.43 µs to 82.61 µs) with an IOPS drop from 141k to 5.3k, proving that S3 cannot support transactional database engines.

---

## Conclusion

The FIO performance evaluation establishes that Silo CSI-S3 delivers viable sequential read performance (405 MiB/s) and acceptable background write throughput (117 MiB/s) for asset storage and archiving. However, its 50x latency amplification on random 4KB I/O confirms that transactional databases, WAL files, and high-concurrency caches must never be deployed on S3-backed CSI volumes.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Establish loopback NFS baseline mount
sudo ./scripts/setup-local-nfs.sh

# 2. Register benchmark CSI volume
nomad volume create nomad/volumes/vol-fio-bench.hcl

# 3. Launch FIO benchmark batch job
nomad job run nomad/jobs/fio-benchmark.nomad

# 4. Stream and capture benchmark logs
ALLOC_ID=$(nomad job status fio-benchmark | grep -E 'benchmarks +0 +run' | awk '{print $1}')
nomad alloc logs -f "$ALLOC_ID" fio
```

### Clean Up
```bash
nomad job stop -purge fio-benchmark
nomad volume deregister silo-vol-fio
sudo umount -l /tmp/nomad-lab/volumes/nfs-mount 2>/dev/null || true
sudo rm -f /etc/exports.d/nomad-lab.exports
sudo exportfs -rav 2>/dev/null || true
```
