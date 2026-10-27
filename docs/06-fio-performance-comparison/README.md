# Sub-Task 6: FIO Performance Benchmark Comparison (DEV-938)

## 1. Executive Summary

To answer whether Silo S3 can serve as an effective network storage substrate for Nomad workloads, raw functional compatibility is only half the question; performance characteristics determine what classes of workloads can realistically run.

This sub-task executes identical, standardized **Flexible I/O Tester (FIO)** benchmarks across three persistent storage tiers in our Nomad cluster:
1. **Local Host SSD Volume:** Direct ext4 host volume (`/mnt/local-ssd`).
2. **Loopback NFS Volume:** In-kernel NFS v3/v4 network share (`/mnt/nfs`).
3. **Silo CSI-S3 Volume:** S3-backed persistent volume managed by Nomad CSI via `s3fs` (`/mnt/silo-csi`).

### Key Performance Findings
* **Sequential Write Penalty:** Silo CSI-S3 achieved **117 MiB/s** compared to **4,571 MiB/s** on Local SSD and **5,818 MiB/s** on NFS (~39x to 50x slower). Each write incurs local FUSE buffer translation, multi-part payload assembly, and HTTP network serialization.
* **Sequential Read Feasibility:** Silo CSI-S3 delivered **405 MiB/s** read throughput. While ~14x slower than local host caching, this bandwidth is more than adequate for media streaming, asset serving, model distribution, and bulk archive extraction.
* **Random 4KB Latency Degradation:** Random 4KB write latency surged from **1.43 µs** (SSD) and **3.30 µs** (NFS) to **82.61 µs** (CSI-S3), while random write IOPS dropped 26x (from 141,000 IOPS to 5,389 IOPS).

---

## 2. Storage Architecture Comparison

```mermaid
flowchart TD
    subgraph Container Workload
        FIO["fio Benchmark Process<br>(fio-benchmark.nomad)"]
    end

    subgraph Tier 1: Local SSD
        FIO -->|Direct VFS Path| VFS1["Linux VFS"]
        VFS1 -->|Direct Block I/O| NVME["Local NVMe SSD<br><b>Throughput: 4,571 MiB/s</b><br>Latency: 26 us"]
    end

    subgraph Tier 2: Loopback NFS
        FIO -->|POSIX Syscalls| VFS2["Linux VFS"]
        VFS2 -->|Kernel NFS Client| KNFS["nfs.ko (Kernel RPC)"]
        KNFS -->|Loopback TCP 2049| NFSD["nfsd (Kernel Server)<br><b>Throughput: 5,818 MiB/s</b><br>Latency: 18 us"]
    end

    subgraph Tier 3: Silo CSI-S3
        FIO -->|POSIX Syscalls| VFS3["Linux VFS"]
        VFS3 -->|/dev/fuse Context Switch| FUSE["s3fs Userspace Daemon"]
        FUSE -->|Local Cache Staging| CACHE["/tmp Cache Buffers"]
        FUSE -->|HTTP REST API (Port 9000)| SILO["Silo Object Store<br><b>Throughput: 117 MiB/s</b><br>Latency: 1,059 us"]
    end
```

---

## 3. Comparative Benchmark Results

All tests were executed using [`nomad/jobs/fio-benchmark.nomad`](file:///var/home/syedadil/personal/silo-nomad-storage-network/nomad/jobs/fio-benchmark.nomad) with pinned `fio v3.36`.

### 1. Sequential Write Performance (128KB block size, 64MB file)
Measures large sequential writes typical of backups, logging, and export pipelines:

| Storage Tier | Bandwidth (MiB/s) | IOPS | Avg Latency | Relative Slowdown |
|---|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **4,571 MiB/s** | 36,600 | 26.35 µs | 1.0x (Baseline) |
| **Loopback NFS** | **5,818 MiB/s** | 46,500 | 18.84 µs | 0.8x |
| **Silo CSI-S3** | **117 MiB/s** | 936 | 1,059.30 µs | **39.1x slower** |

### 2. Sequential Read Performance (128KB block size, 64MB file)
Measures bulk sequential reading typical of dataset loading, media ingestion, and web asset streaming:

| Storage Tier | Bandwidth (MiB/s) | IOPS | Avg Latency | Relative Slowdown |
|---|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **5,818 MiB/s** | 46,500 | 19.30 µs | 1.0x (Baseline) |
| **Loopback NFS** | **4,571 MiB/s** | 36,600 | 25.20 µs | 1.3x |
| **Silo CSI-S3** | **405 MiB/s** | 3,240 | 286.19 µs | **14.4x slower** |

### 3. Random 4KB Read/Write (70% Read / 30% Write mix, 16MB file)
Simulates transactional metadata and small-block database activity:

| Storage Tier | Read IOPS | Read BW | Write IOPS | Write BW | Avg Write Latency |
|---|:---:|:---:|:---:|:---:|:---:|
| **Local Host SSD** | **314,000** | 1,226 MiB/s | **141,000** | 552 MiB/s | 1.43 µs |
| **Loopback NFS** | **80,700** | 315 MiB/s | **36,300** | 142 MiB/s | 3.30 µs |
| **Silo CSI-S3** | **12,000** | 46.7 MiB/s | **5,389** | 21.1 MiB/s | 82.61 µs |

*(Raw benchmark output preserved in [`docs/06-fio-performance-comparison/evidence/fio-raw-output.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/06-fio-performance-comparison/evidence/fio-raw-output.txt) and tabulated summary in [`docs/06-fio-performance-comparison/evidence/fio-summary-table.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/06-fio-performance-comparison/evidence/fio-summary-table.txt)).*

---

## 4. Workload Suitability Matrix

Based on our empirical metrics, workloads are categorized as follows:

| Workload Profile | Typical Examples | Silo CSI-S3 Viability | Primary Bottleneck |
|---|---|:---:|---|
| **Media / Asset Distribution** | Nginx uploads, user avatars, PDF reports, static video assets | **EXCELLENT** | None; 405 MiB/s read bandwidth exceeds 10GbE network link saturation. |
| **Cold Storage / Archiving** | Nightly database dumps, rotated syslog archives, tarballs | **GOOD** | Sequential writes (117 MiB/s) are adequate for background exports. |
| **Batch Big Data Processing** | Spark/Flink input data, ML model weights, read-only datasets | **GOOD** | Read-heavy patterns benefit from local kernel pagecache once primed. |
| **Software Builds / Caches** | Gradle/Maven caches, Go module proxies, NPM directories | **POOR** | Thousands of small 4KB reads/writes incur severe HTTP latency. |
| **ACID / Transactional DBs** | SQLite, PostgreSQL data directories, Redis RDB/AOF, etcd | **UNUSABLE** | Catastrophic latency; lack of fsync atomicity guarantees corrupts WAL. |

---

## 5. Reproduction Steps

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
