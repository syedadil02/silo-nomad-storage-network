# Sub-Task 3: CSI Plugin Deployment & Volume Claims (DEV-935)

## Goal

Deploy the Container Storage Interface (CSI) plugin [`mwantia/nomad-csi-s3-plugin`](https://github.com/mwantia/nomad-csi-s3-plugin) to the multi-node Nomad cluster using a decoupled Controller and Node daemon topology. Dynamically provision credentials via Nomad Variables, register CSI volumes pointing to our local Silo S3 backend, and empirically verify end-to-end volume claim, mount, and data persistence with a containerized consumer workload.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **CSI Plugin Image:** `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Silo Backend Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **Consumer Workload Image:** `docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Local Machine:** Physical host running 1 Server + 2 Clients (`nomad-client-1`, `nomad-client-2`)
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Multi-node Nomad cluster operational (`nomad-client-1` and `nomad-client-2` in `ready` status).
* Silo backend running on `http://127.0.0.1:9000` with bucket `nomad-tests` initialized.
* Nomad Variable `nomad/jobs/csi-s3-plugin` populated with S3 credentials (`access_key`, `secret_key`).

---

## Step-by-Step Procedure & Verification

### Step 1: Deploy Decoupled CSI Controller & Node Plugins
* **Command:**
  ```bash
  nomad job run nomad/jobs/csi-s3-controller.nomad
  nomad job run nomad/jobs/csi-s3-node.nomad
  nomad plugin status silo-s3-csi
  ```
* **Expected Result:** Controller job starts as singleton (`count = 1`, `type = "service"`) on one client; Node daemon runs as `type = "system"` across both clients. `nomad plugin status` reports 1 controller and 2 nodes healthy.
* **Actual Result:** **PASS**. Plugin `silo-s3-csi` registered with 1 healthy controller and 2 healthy nodes.
* **Evidence:** Captured in [`evidence/plugin-status.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/plugin-status.txt).

### Step 2: Register CSI Volumes (Alias & Direct Secret Modes)
* **Command:**
  ```bash
  nomad volume create nomad/volumes/vol-single-alias.hcl
  nomad volume create nomad/volumes/vol-single-direct.hcl
  nomad volume status silo-vol-alias
  ```
* **Expected Result:** Volumes register in Nomad catalog with `Schedulable = true`, pointing to external ID `nomad-tests/vol-single-alias`.
* **Actual Result:** **PASS**. Both volumes registered successfully.
* **Evidence:** Captured in [`evidence/volume-status-alias.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/volume-status-alias.txt) and [`evidence/volume-status-direct.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/volume-status-direct.txt).

### Step 3: Deploy Consumer Workload Claiming CSI Volume
* **Command:**
  ```bash
  nomad job run nomad/jobs/consumer-single-writer.nomad
  ALLOC_ID=$(nomad job status consumer-single-writer | grep -E 'writer +0 +run' | awk '{print $1}')
  nomad alloc logs "$ALLOC_ID" writer
  ```
* **Expected Result:** Consumer starts, mounts `/data` via CSI, writes a timestamped payload to `/data/csi-message.txt`, and logs success.
* **Actual Result:** **PASS**. Consumer allocation launched, claimed `silo-vol-alias`, wrote the payload, and verified readback in container stdout.
* **Evidence:** Captured in [`evidence/consumer-writer-status.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/consumer-writer-status.txt) and [`evidence/consumer-writer-logs.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/consumer-writer-logs.txt).

### Step 4: Verify Object Store Persistence in Silo S3 Backend
* **Command:**
  ```bash
  mc ls --recursive local/nomad-tests/vol-single-alias
  mc cat local/nomad-tests/vol-single-alias/csi-message.txt
  ```
* **Expected Result:** The file `/data/csi-message.txt` written inside the container exists as an object in the Silo S3 bucket with identical content.
* **Actual Result:** **PASS**. Silo object store contains `vol-single-alias/csi-message.txt` (75 bytes) with exact timestamp payload.
* **Evidence:** Captured in [`evidence/silo-bucket-ls.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/silo-bucket-ls.txt) and [`evidence/silo-csi-message-content.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/03-csi-plugin-deployment/evidence/silo-csi-message-content.txt).

---

## Results Table

| Step / Component | Target | Expected Status | Actual Status | Verification Output |
|---|---|:---:|:---:|---|
| **CSI Controller** | `csi-s3-controller` | 1 Healthy | **PASS** | Registered on `nomad-client-1` (`326a5043`) |
| **CSI Node Daemons**| `csi-s3-node` | 2 Healthy | **PASS** | Active on `nomad-client-1` and `nomad-client-2` |
| **Volume Registration** | `silo-vol-alias` | Schedulable | **PASS** | Target `nomad-tests/vol-single-alias` registered |
| **Consumer Claim** | `consumer-single-writer`| Running | **PASS** | Mounted `/data`, wrote `csi-message.txt` |
| **Backend Persistence**| Silo S3 Object Store | 75B Object | **PASS** | Verified via `mc cat` in bucket `nomad-tests` |

---

## Findings & Problems Resolved

1. **Decoupled Architecture Requirement:** Running the CSI plugin as a monolith in a `system` job schedules 2 controllers competing for volume mutations without leader election. Splitting into a singleton controller (`count = 1`, `type = "service"`) and node mounters (`type = "system"`) guarantees safe operations.
2. **Dynamic Credential Templating:** Rendered `/secrets/config.yml` inside plugin containers via Nomad Go templates querying `nomadVar "nomad/jobs/csi-s3-plugin"`, eliminating plaintext secrets from source control.
3. **Prefix Isolation:** Using `usePrefix = "true"` and `prefix = "vol-single-alias"` allows multiple independent Nomad volumes to securely share a single Silo S3 bucket without collisions.

---

## Conclusion

The Nomad CSI S3 driver (`mwantia/nomad-csi-s3-plugin:v1.0.4`) successfully bridges Nomad container workloads to the local Silo S3 storage substrate. Volume claims, userspace FUSE staging, container bind mounts, and persistent S3 object commits function cleanly for single-writer workloads under the decoupled controller/node architecture.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Deploy CSI Controller & Nodes
nomad job run nomad/jobs/csi-s3-controller.nomad
nomad job run nomad/jobs/csi-s3-node.nomad

# 2. Verify Plugin Registration
nomad plugin status silo-s3-csi

# 3. Register CSI Volume
nomad volume create nomad/volumes/vol-single-alias.hcl
nomad volume status silo-vol-alias

# 4. Deploy Consumer Workload
nomad job run nomad/jobs/consumer-single-writer.nomad

# 5. Verify Content in Silo Backend Bucket
mc ls --recursive local/nomad-tests/vol-single-alias
mc cat local/nomad-tests/vol-single-alias/csi-message.txt
```

### Clean Up
```bash
nomad job stop -purge consumer-single-writer
nomad volume deregister silo-vol-alias
nomad job stop -purge csi-s3-controller csi-s3-node
```
