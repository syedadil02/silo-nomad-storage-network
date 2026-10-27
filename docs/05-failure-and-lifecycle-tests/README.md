# Sub-Task 5: Chaos, Failure Modes & Node Drain Rescheduling (DEV-937)

## Goal

Subject the Silo + Nomad CSI S3 storage infrastructure to three real-world operational chaos and lifecycle failure scenarios:
1. **Backend Outage:** Stopping the underlying Silo S3 server and evaluating workload behavior before and after backend restoration.
2. **CSI Daemon Crash:** Terminating the CSI node mounter daemon to characterize userspace FUSE socket severance and in-place restart behavior.
3. **Node Drain Rescheduling:** Evicting a client node via `nomad node drain` to verify cross-node volume detachment, re-scheduling, and data durability.

---

## Environment

* **Nomad Version:** `Nomad v1.7.5`
* **CSI Plugin Image:** `docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c`
* **Silo Backend Image:** `docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c`
* **Consumer Image:** `docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e`
* **Host Operating System:** Fedora Silverblue 44 (Linux `7.2.11-200.fc44.x86_64`)
* **Local Machine:** Physical host running 1 Server + 2 Clients (`nomad-client-1`, `nomad-client-2`)
* **Date of Evaluation:** October 28, 2026

---

## Prerequisites

* Active Nomad cluster with healthy `silo-s3-csi` controller and node daemons.
* Operational Silo S3 backend on `http://127.0.0.1:9000`.
* Active consumer workload (`consumer-single-writer`) claiming `silo-vol-alias`.

---

## Step-by-Step Procedure & Verification

### Step 1: Scenario A - Backend Outage & Recovery
* **Command:**
  ```bash
  nomad job stop silo
  nomad alloc exec "$CONSUMER_ALLOC" sh -c 'cat /data/csi-message.txt' || true
  nomad job run nomad/jobs/silo.nomad
  nomad alloc exec "$CONSUMER_ALLOC" sh -c 'cat /data/csi-message.txt'
  nomad alloc exec "$CONSUMER_ALLOC" sh -c 'echo "written after backend recovery" > /data/recovery-test.txt'
  mc ls local/nomad-tests/vol-single-alias/recovery-test.txt
  ```
* **Expected Result:** Consumer operations return `EIO` (I/O error) while Silo is offline. Once Silo restarts, `s3fs` automatically resumes read and write operations without requiring a container restart.
* **Actual Result:** **PASS**. Read returned `cat: can't open '/data/csi-message.txt': I/O error` during the outage. Immediately upon Silo restoration, reads and new writes succeeded seamlessly.
* **Evidence:** Captured in [`evidence/backend-stoppage-eio.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/05-failure-and-lifecycle-tests/evidence/backend-stoppage-eio.txt) and [`evidence/backend-recovery.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/05-failure-and-lifecycle-tests/evidence/backend-recovery.txt).

### Step 2: Scenario B - CSI Node Plugin Crash & FUSE Disconnection
* **Command:**
  ```bash
  NODE_ALLOC=$(nomad job status csi-s3-node | grep -E 'node +0 +run' | head -n 1 | awk '{print $1}')
  nomad alloc restart "$NODE_ALLOC" plugin
  nomad alloc exec "$CONSUMER_ALLOC" sh -c 'ls -la /data' || true
  nomad alloc restart "$CONSUMER_ALLOC" app || true
  ```
* **Expected Result:** Terminating the mounter daemon severs the userspace FUSE socket. Active containers see `ENOTCONN` (Socket not connected). In-place restarts fail due to broken mount points.
* **Actual Result:** **PASS (Failure Mode Confirmed)**. Active container returned `ls: /data: Socket not connected`. In-place restart failed with Nomad error: `API error (500): container create: transport endpoint is not connected`.
* **Evidence:** Captured in [`evidence/plugin-restart-disconnection.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/05-failure-and-lifecycle-tests/evidence/plugin-restart-disconnection.txt).

### Step 3: Scenario C - Client Node Drain & Failover Rescheduling
* **Command:**
  ```bash
  nomad alloc exec "$CONSUMER_ALLOC" sh -c 'echo "Pre-drain state recorded at $(date)" > /data/failover-evidence.txt'
  NODE_ID=$(nomad node status | grep nomad-client-1 | awk '{print $1}')
  nomad node drain -enable -deadline 1m "$NODE_ID"
  # Wait for rescheduling to nomad-client-2
  NEW_ALLOC=$(nomad job status consumer-single-writer | grep -E 'writer +0 +run' | awk '{print $1}')
  nomad alloc exec "$NEW_ALLOC" cat /data/failover-evidence.txt
  ```
* **Expected Result:** Draining Node 1 terminates the local consumer, detaches the volume, schedules the task group onto Node 2, stages the volume via Node 2's CSI daemon, and preserves the payload.
* **Actual Result:** **PASS**. Workload rescheduled onto `nomad-client-2`. Pre-drain file `/data/failover-evidence.txt` was read back intact.
* **Evidence:** Captured in [`evidence/node-drain-migration.txt`](file:///var/home/syedadil/personal/silo-nomad-storage-network/docs/05-failure-and-lifecycle-tests/evidence/node-drain-migration.txt).

---

## Results Table

| Chaos Scenario | Injected Fault | Observed Behavior | Recovery Mechanism | Recovery Status |
|---|---|---|---|:---:|
| **A. Backend Outage** | Silo stopped (`nomad job stop silo`) | Active reads returned `EIO` (`Input/output error`). | Restarted Silo; `s3fs` automatically resumed I/O without container restart. | **AUTO-RECOVERED** |
| **B. Node Plugin Crash** | `csi-s3-node` daemon restarted | FUSE socket severed: `ls: /data: Socket not connected` (`ENOTCONN`). In-place restart failed. | Requires fresh allocation rescheduling and lazy unmount (`umount -l`). | **REQUIRES RESCHEDULE** |
| **C. Node Drain** | `nomad node drain -enable` on Node 1 | Allocation migrated to Node 2; volume unmounted, restaged, and remounted. | Pre-drain data (`failover-evidence.txt`) verified intact on new node. | **PERSISTENCE VERIFIED** |

---

## Findings & Problems Resolved

1. **FUSE Userspace Socket Fragility:** Unlike kernel network filesystems (NFS), FUSE mounts depend on an active user-space daemon holding `/dev/fuse`. If the daemon crashes, the kernel marks the mount `ENOTCONN`. In-place container restarts fail; the allocation must be destroyed, lazily unmounted (`umount -l`), and scheduled fresh.
2. **Storage Co-location Hazard:** Draining a client hosting both storage (Silo) and compute kills the storage backend for surviving nodes. Silo must be hosted on dedicated nodes exempt from worker drains.
3. **Template Change Mode Policy:** Stateful backend services must configure `change_mode = "noop"` in Nomad template blocks to prevent unexpected restarts from severing client FUSE sockets.

---

## Conclusion

The Silo S3 CSI storage network demonstrates robust automatic recovery from transient backend network and server outages. However, userspace FUSE crashes sever active mount sockets, requiring automated lazy-unmount cleanups and fresh allocation rescheduling. With dedicated storage node isolation and proper drain policies, seamless workload failover and data durability are achieved.

---

## How to Reproduce and Clean Up

### Reproduce
```bash
# 1. Test backend outage and recovery
nomad job stop silo
nomad alloc exec "$CONSUMER_ALLOC" cat /data/csi-message.txt || true
nomad job run nomad/jobs/silo.nomad
nomad alloc exec "$CONSUMER_ALLOC" cat /data/csi-message.txt

# 2. Test plugin daemon crash
NODE_ALLOC=$(nomad job status csi-s3-node | grep -E 'node +0 +run' | head -n 1 | awk '{print $1}')
nomad alloc restart "$NODE_ALLOC" plugin

# 3. Test node drain rescheduling
NODE_ID=$(nomad node status | grep nomad-client-1 | awk '{print $1}')
nomad node drain -enable -deadline 1m "$NODE_ID"
```

### Clean Up
```bash
# Re-enable drained node
nomad node drain -disable "$NODE_ID"
```
