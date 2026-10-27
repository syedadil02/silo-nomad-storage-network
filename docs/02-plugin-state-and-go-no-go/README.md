# Sub-Task 2: CSI Plugin State Audit & Go/No-Go Assessment (DEV-934)

## Goal

Perform a deep architectural and security audit of the Container Storage Interface (CSI) plugin [`mwantia/nomad-csi-s3-plugin`](https://github.com/mwantia/nomad-csi-s3-plugin) to evaluate its code maturity, upstream maintenance health, CLI flag capabilities, underlying FUSE implementation, and suitability as a persistent storage driver connecting Nomad workloads to our Silo S3 backend. Establish a formal Go/No-Go decision before deploying to cluster nodes.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **CSI Plugin Evaluated:** `mwantia/nomad-csi-s3-plugin`
  * Tag `v1.0.1`: `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1@sha256:b72f1a95a85859463513cd79c95c49f43740ab74ad07480653c1a75900369d06`
  * Tag `v1.0.4` (`latest`): `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Underlying FUSE Stack:** `/usr/bin/s3fs` V1.89 with GnuTLS(gcrypt) and `bindfs`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Local Machine:** Physical host running rootful Podman socket at `/run/podman/podman.sock`
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Active network connectivity to query GitHub API and Docker Hub registry.
* Container runtime CLI (`podman` or `docker`) with privileges to pull and inspect container layers.
* JSON parsing utility (`jq`) for auditing upstream repository commits and tags.

---

## Step-by-Step Procedure & Verification

### Step 1: Upstream Repository Audit & Maintenance Health Check
* **Command:**
  ```bash
  curl -s https://api.github.com/repos/mwantia/nomad-csi-s3-plugin | jq '{name, full_name, created_at, pushed_at, open_issues_count}'
  curl -s https://api.github.com/repos/mwantia/nomad-csi-s3-plugin/commits | jq -r '.[] | "\(.commit.author.date) | \(.sha[:8]) | \(.commit.message | split("\n")[0])"'
  ```
* **Expected Result:** Discover upstream repository metrics, commit velocity, and author activity.
* **Actual Result:** **PASS (High Risk Observed)**. Project contains only 17 total commits created over a 5-day span (Oct 27–31, 2024), authored by a single developer (`mwantia`), with zero commits or releases since October 31, 2024.
* **Evidence:** Raw API payloads captured in [`evidence/github-repo-audit.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/github-repo-audit.txt) and [`evidence/github-commits.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/github-commits.txt).

### Step 2: Container Image Tags & Digest Inspection
* **Command:**
  ```bash
  sudo podman pull docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1
  sudo podman pull docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4
  sudo podman inspect docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1 --format '{{.Digest}}'
  sudo podman inspect docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 --format '{{.Digest}}'
  ```
* **Expected Result:** Verify immutable SHA256 digests for all published release tags.
* **Actual Result:** **PASS**. Successfully resolved immutable digests for `v1.0.1` and `v1.0.4`. `v1.0.4` matches `latest` with configuration hash `2bc9725d30`.
* **Evidence:** Captured in [`evidence/plugin-tags-and-digests.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/plugin-tags-and-digests.txt).

### Step 3: Flag Gap Verification between `v1.0.1` and `v1.0.4`
* **Command:**
  ```bash
  sudo podman run --rm docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1 --nodeid test --config=/dev/null || true
  sudo podman run --rm docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 --help
  ```
* **Expected Result:** Verify whether the documented `-config` flag for dynamic credential aliases is supported in both versions.
* **Actual Result:** **PASS (Critical Discrepancy Found)**. In `v1.0.1`, running with `--config` fails immediately: `flag provided but not defined: -config`. Tag `v1.0.4` properly implements `-config` and YAML alias parsing via `spf13/viper`.
* **Evidence:** Captured in [`evidence/plugin-v1.0.1-help.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/plugin-v1.0.1-help.txt) and [`evidence/plugin-v1.0.4-help.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/plugin-v1.0.4-help.txt).

### Step 4: Underlying FUSE Stack Audit
* **Command:**
  ```bash
  sudo podman run --rm --entrypoint /usr/bin/s3fs docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 --version
  ```
* **Expected Result:** Identify the user-space filesystem bridge used to interface with S3.
* **Actual Result:** **PASS**. Returns `Amazon Simple Storage Service File System V1.89 with GnuTLS(gcrypt)`. Bundled helper `bindfs` is also present for staging directory binds.
* **Evidence:** Captured in [`evidence/s3fs-version.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/02-plugin-state-and-go-no-go/evidence/s3fs-version.txt).

---

## Results Table

### 1. Formal Go/No-Go Decision Matrix

| Dimension | Weight | Score (1-5) | Rationale |
|---|:---:|:---:|---|
| **Nomad CSI Spec Adherence** | High | 4/5 | Properly implements Controller and Node CSI gRPC services for Nomad v1.3+. |
| **Operational Simplicity** | Medium | 4/5 | Deploys cleanly as standard Nomad job specifications; uses standard S3 credentials. |
| **Community & Maintenance** | High | 1/5 | Inactive upstream since October 2024; single author; 0 stars. |
| **POSIX Semantics & Safety** | Critical | 2/5 | Subject to `s3fs` object store emulation risks (no atomicity guarantees, eventual consistency latency). |
| **Workload Suitability** | High | 3/5 | Suitable for read-heavy or asset storage; catastrophic for write-heavy databases (SQLite, PostgreSQL). |

### 2. Alternative Solutions Survey

| Solution | Mechanism | Nomad Native? | Status / Evaluation |
|---|---|---|---|
| **`mwantia/nomad-csi-s3-plugin`** | Nomad CSI (`s3fs` + `bindfs`) | Yes | Sole active Nomad-targeted S3 CSI driver. Selected for evaluation. |
| **`ctrox/csi-s3`** | Kubernetes CSI (`s3fs`, `geese`, `rclone`) | No (K8s) | Upstream ancestor. Abandoned with unmerged PRs; does not support Nomad mount staging paths. |
| **Static Host FUSE (`s3fs` fallback)** | Host mount via `/usr/bin/s3fs` -> Nomad Host Volume | Partial | Evaluated in Sub-Task 7. Reliable fallback, but bypasses Nomad CSI scheduling and dynamic provisioning. |
| **Native Nomad NFS Volume** | Kernel NFS client -> Nomad Host Volume | Native | Industry standard for shared POSIX storage in Nomad. Evaluated as benchmark baseline in Sub-Task 6. |
| **Vendor CSI Drivers (EBS, Ceph, etc.)** | Block / Distributed FS CSI | Native | Production-ready, but tied to specific cloud vendors or require heavy Ceph clusters rather than lightweight S3 object storage. |

---

## Findings & Problems Resolved

1. **Flag Gap in `v1.0.1`:** Tag `v1.0.1` crashes if passed `-config=/secrets/config.yml`. Must pin `v1.0.4` (`sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`), which implements the flag and YAML alias support.
2. **Upstream Abandonment:** The upstream repository has been abandoned since October 31, 2024. For production use, the repository must be internally vendored and maintained.
3. **Privilege Requirements:** The container requires `privileged = true` and host `/dev/fuse` access to mount FUSE filesystems into Nomad allocation paths.

---

## Conclusion

### Verdict: **PROCEED WITH RESERVATIONS (GO-WITH-CONDITIONS)**

The plugin demonstrates functional Nomad CSI contracts and packages the necessary FUSE tooling (`s3fs v1.89`). However, due to its single-maintainer status and inherent POSIX-over-S3 limitations, it can only proceed under four mandatory conditions:
1. **Pin Immutable Image Digest:** Deploy `v1.0.4` with digest `sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`.
2. **Split Deployment Topology:** Run 1 Controller instance (`type = "service"`, `count = 1`) and client node daemons (`type = "system"`).
3. **Strict Workload Boundary:** Forbid ACID databases and concurrent multi-writer appends.
4. **FUSE Fallback Retained:** Maintain the static host FUSE fallback (Sub-Task 7) as an operational disaster-recovery alternative.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Query upstream GitHub metadata
curl -s https://api.github.com/repos/mwantia/nomad-csi-s3-plugin | jq '{name, full_name, created_at, pushed_at, open_issues_count}'

# 2. Inspect commit history
curl -s https://api.github.com/repos/mwantia/nomad-csi-s3-plugin/commits | jq -r '.[] | "\(.commit.author.date) | \(.sha[:8]) | \(.commit.message | split("\n")[0])"'

# 3. Pull and inspect v1.0.1
sudo podman pull docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1
sudo podman inspect docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1 --format '{{.Digest}}'
sudo podman run --rm docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1 --help || true

# 4. Pull and inspect v1.0.4
sudo podman pull docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4
sudo podman inspect docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 --format '{{.Digest}}'
sudo podman run --rm docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 --help
```

### Clean Up
```bash
sudo podman rmi docker.io/mwantia/nomad-csi-s3-plugin:v1.0.1 docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4 2>/dev/null || true
```
