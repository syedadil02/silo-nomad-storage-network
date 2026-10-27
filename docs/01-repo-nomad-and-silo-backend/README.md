# Sub-task 1: Repo Setup, Local Nomad Cluster & Silo Backend (DEV-933)

## Goal
Establish a reproducible, clean local Nomad environment comprising a single-server cluster orchestrating two independent client nodes, configured with Docker driver privileged capabilities, backed by a pinned, single-node Silo S3-compatible object storage service deployed as a Nomad job. Validate secret scanning, verify S3 connectivity using the MinIO client (`mc`), and record cluster rebuild benchmarks.

---

## Environment
* **Date:** 2026-10-28
* **Host Operating System:** Linux (Fedora Silverblue / Atomic Desktop, kernel 7.2.11-200.fc44.x86_64)
* **Nomad Version:** `Nomad v1.7.5` (BuildDate: 2024-02-13T15:10:13Z, Revision: `5f5d4646198d09b8f4f6cb90fb5d50b53fa328b8`)
* **Container Engine:** Podman 5.8.9 (Docker API compatibility socket at `/run/podman/podman.sock`)
* **OCI Runtime:** `runc version 1.2.5` (commit: `v1.2.5-0-g59923ef1`, libseccomp: `2.5.5`)
* **Silo Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **MinIO Client (`mc`) Version:** `RELEASE.2026-10-26T00-00-00Z` (commit-id: `0ceb298cdcd05f2ffdc4ea62d7d01a3666c3e8cc`)

---

## Prerequisites
1. Dedicated cluster directories under `/tmp/nomad-lab` labeled with `container_file_t` SELinux context.
2. Rootful Podman socket enabled via `sudo systemctl enable --now podman.socket`.
3. Pre-commit hooks installed (`gitleaks v8.21.2`).
4. Passwordless `sudo` configured for lab scripts managing Nomad client mount namespaces.

---

## Step-by-Step Procedure & Verification

### Step 1: Pre-Commit Secret Interception Verification
* **Command:**
  ```bash
  echo 'ghp_SAMPLE_FAKE_PAT_TOKEN_FOR_GITLEAKS_TEST' > test_fake_secret.txt
  git add test_fake_secret.txt
  git commit -m "ST01: test secret blocker"
  ```
* **Expected Result:** Gitleaks pre-commit hook intercepts the staged GitHub PAT token and aborts the commit with exit code 1.
* **Actual Result:** **PASS**. Gitleaks flagged `Finding: REDACTED RuleID: github-pat leaks found: 1` and aborted the commit.
* **Evidence:** `evidence/gitleaks-blocked.txt`

### Step 2: Bootstrap 2-Node Nomad Cluster
* **Command:**
  ```bash
  sudo ./scripts/nomad-up
  ```
* **Expected Result:** `nomad-client-1` (Server + Client) and `nomad-client-2` (Client on ports 4656-4658) join the cluster and reach `ready` status.
* **Actual Result:** **PASS**. Both clients joined and reached `eligible/ready`.
* **Evidence:** `evidence/nomad-node-status.txt`

### Step 3: Verify Docker Driver & Privileged Execution Capability
* **Command:**
  ```bash
  nomad node status -self -verbose | grep -E "driver\.docker|privileged"
  ```
* **Expected Result:** `driver.docker = 1` and `driver.docker.privileged.enabled = true`.
* **Actual Result:** **PASS**. The Docker driver reported privileged mode enabled and healthy.
* **Evidence:** `evidence/docker-allow-privileged.txt`

### Step 4: Populate Nomad Variables & Deploy Pinned Silo Backend
* **Command:**
  ```bash
  nomad var put -force nomad/jobs/silo \
    root_user="<SILO_ROOT_USER>" \
    root_password="<SILO_ROOT_PASSWORD>" \
    test_access_key="<CSI_ACCESS_KEY>" \
    test_secret_key="<CSI_SECRET_KEY>"
  nomad job run nomad/jobs/silo.nomad
  ```
* **Expected Result:** Silo service starts in `host` network mode, binds static ports 9000 (S3) and 9001 (Console), mounts host volume `silo-data`, and registers a passing health check.
* **Actual Result:** **PASS**. Deployment `dc00dc9c` completed successfully with allocation running and HTTP health check passing.

### Step 5: Initialize Bucket & Dedicated CSI Service Account
* **Command:**
  ```bash
  nomad job run nomad/jobs/silo-init-mc.nomad
  ```
* **Expected Result:** Batch job sets alias, verifies `mc admin info local`, creates bucket `nomad-tests`, puts and gets a test object, provisions dedicated CSI access keys, and verifies access.
* **Actual Result:** **PASS**. Bucket `nomad-tests` created, put/get validated, and dedicated CSI access key verified.
* **Evidence:** `evidence/mc-admin-info-and-put-get.txt` and `evidence/mc-put-get.txt`

### Step 6: Cluster Teardown and Rebuild Benchmark
* **Command:**
  ```bash
  sudo ./scripts/nomad-reset
  ```
* **Expected Result:** Teardown of all running containers and Nomad agents, clean lazy-unmount of allocation volumes, and full cluster rebuild with timing logged.
* **Actual Result:** **PASS**. Rebuild completed and validated in **12 seconds**.
* **Evidence:** `evidence/nomad-rebuild-time.txt`

---

## Results Table

| Check / Requirement | Target / Metric | Result | Status |
| :--- | :--- | :--- | :--- |
| **Gitleaks Pre-commit Hook** | Block secret commit | Leaks found: 1, Exit code: 1 | **PASS** |
| **Nomad Version** | v1.3.0 or later | `Nomad v1.7.5` | **PASS** |
| **Client Node Readiness** | 2 Ready clients | `nomad-client-1`, `nomad-client-2` ready | **PASS** |
| **Docker Driver Privileged** | `allow_privileged = true` | `driver.docker.privileged.enabled = true` | **PASS** |
| **Silo Image Tag & Digest** | Pinned `RELEASE.*` & sha256 | `pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ec...` | **PASS** |
| **Silo S3 Functionality** | Put/Get object via `mc` | Object `test.txt` put and verified | **PASS** |
| **CSI Key Verification** | Dedicated service account | S3 bucket access validated via CSI key | **PASS** |
| **Rebuild Time** | Repo-driven reset | **12 seconds** | **PASS** |

---

## Findings & Problems Resolved

1. **Nomad Loopback Advertisement:** Nomad rejects binding to `127.0.0.1` without an explicit `advertise` block. Resolved by defining distinct `advertise { http, rpc, serf }` stanzas for each client.
2. **Cgroups v2 Swappiness Conflict:** Under cgroups v2, the default `crun` OCI runtime rejects `MemorySwappiness = -1` passed by Nomad's Docker driver. Resolved by deploying standalone `runc v1.2.5` and configuring Podman's OCI runtime to use `runc`.
3. **SELinux Volume Relabeling:** Host volumes mounted into containers required the `container_file_t` SELinux context to permit write access under Fedora's enforcing policy. Automated inside `scripts/nomad-up`.
4. **Allocation Mount Cleanup on Reset:** Teardown required unmounting lingering tmpfs allocation mounts (`/proc/mounts`) before wiping `/tmp/nomad-lab` to prevent `Device or resource busy` errors. Handled gracefully in `scripts/nomad-reset`.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Start cluster
sudo ./scripts/nomad-up

# 2. Populate secrets into Nomad Variables
nomad var put -force nomad/jobs/silo \
  root_user="silo_admin" \
  root_password="silo_password_secure" \
  test_access_key="csi_key_test" \
  test_secret_key="csi_sec_test_secure"

# 3. Deploy backend and initialize bucket
nomad job run nomad/jobs/silo.nomad
nomad job run nomad/jobs/silo-init-mc.nomad
```

### Clean Up
```bash
sudo ./scripts/nomad-down
```
