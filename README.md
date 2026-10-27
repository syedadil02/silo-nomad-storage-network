# Silo + Nomad S3 CSI Storage Network Evaluation (DEV-932)

> **Evaluation Project Note:** This repository is an engineering proof-of-concept and evaluation lab testing whether **Silo** (an S3-compatible distributed object store) can serve as a persistent network storage substrate for arbitrary Nomad workloads via Nomad's Container Storage Interface (CSI) integration.

---

## Purpose & Scope

Nomad workloads requiring persistent storage traditionally rely on host volumes, dedicated NFS clusters, or cloud block storage. This evaluation explores whether an ordinary, arbitrary Nomad job can mount a persistent volume backed by Silo through Nomad CSI, emulating a POSIX filesystem on top of S3 via `s3fs`.

* **Jira Epic:** `DEV-932` (Nomad + Silo Network Storage Substrate)
* **Target CSI Plugin:** [`mwantia/nomad-csi-s3-plugin`](https://github.com/mwantia/nomad-csi-s3-plugin)
* **Orchestration:** HashiCorp Nomad v1.7.5 (1 Server + 2 Clients)
* **Backend:** Pinned Silo S3 server (`pgsty/silo`)

---

## Sub-Task Status Matrix

| Sub-Task | Jira Key | Focus Area | Status | Documentation / Evidence |
| :--- | :--- | :--- | :---: | :--- |
| **ST01** | DEV-933 | Repo setup, 2-client Nomad cluster, and pinned Silo backend | **Done** | [docs/01-repo-nomad-and-silo-backend](docs/01-repo-nomad-and-silo-backend/README.md) |
| **ST02** | DEV-934 | Re-verify CSI plugin state, commits, issues, and Go/No-Go | **Done** | [docs/02-plugin-state-and-go-no-go](docs/02-plugin-state-and-go-no-go/README.md) |
| **ST03** | DEV-935 | Deploy CSI plugin (Controller + Node) and mount S3 volumes | **Done** | [docs/03-csi-plugin-deployment](docs/03-csi-plugin-deployment/README.md) |
| **ST04** | DEV-936 | POSIX semantics torture tests & multi-writer concurrency | **Done** | [docs/04-posix-semantics-tests](docs/04-posix-semantics-tests/README.md) |
| **ST05** | DEV-937 | Chaos, failure modes, and client node drain rescheduling | **Done** | [docs/05-failure-and-lifecycle-tests](docs/05-failure-and-lifecycle-tests/README.md) |
| **ST06** | DEV-938 | FIO performance benchmarks (CSI-S3 vs Local SSD vs NFS) | **Done** | [docs/06-fio-performance-comparison](docs/06-fio-performance-comparison/README.md) |
| **ST07** | DEV-939 | Static Host-Managed FUSE volume fallback (no CSI) | **Done** | [docs/07-fuse-host-volume-fallback](docs/07-fuse-host-volume-fallback/README.md) |
| **ST08** | DEV-940 | Final Written Recommendation & Workload Viability Report | **Ready** | [docs/08-final-recommendation](docs/08-final-recommendation/README.md) |
| **ST05** | DEV-937 | Chaos, failure modes, and client node drain rescheduling | **Backlog** | [docs/05-failure-and-lifecycle-tests](docs/05-failure-and-lifecycle-tests/README.md) |
| **ST06** | DEV-938 | FIO performance benchmarks (CSI-S3 vs Local SSD vs NFS) | **Backlog** | [docs/06-fio-performance-comparison](docs/06-fio-performance-comparison/README.md) |
| **ST07** | DEV-939 | Static Host-Managed FUSE volume fallback (no CSI) | **Backlog** | [docs/07-fuse-host-volume-fallback](docs/07-fuse-host-volume-fallback/README.md) |
| **ST08** | DEV-940 | Final Written Recommendation & Workload Viability Report | **Backlog** | [docs/08-final-recommendation](docs/08-final-recommendation/README.md) |

---

## Security & Secrets Management
* **Zero Hardcoded Secrets:** Credentials, access keys, and passwords are never committed to this repository. All credentials are dynamically resolved at runtime using **Nomad Variables** (`nomadVar`).
* **Automated Secret Scanning:** Pre-commit hooks (`gitleaks`) actively scan staged files before every commit, blocking hardcoded tokens, AWS keys, and private credentials.

---

## Repository Structure

```text
├── .gitignore
├── .pre-commit-config.yaml
├── README.md
├── nomad/
│   ├── agents/
│   │   ├── client1.hcl
│   │   └── client2.hcl
│   ├── jobs/
│   │   ├── silo.nomad
│   │   ├── silo-init-mc.nomad
│   │   ├── csi-s3-controller.nomad
│   │   ├── csi-s3-node.nomad
│   │   ├── consumer-single-writer.nomad
│   │   ├── consumer-multi-writer.nomad
│   │   ├── fio-benchmark.nomad
│   │   └── consumer-fuse-fallback.nomad
│   └── volumes/
│       ├── vol-single-alias.hcl
│       ├── vol-single-direct.hcl
│       ├── vol-multi-writer.hcl
│       └── vol-fio-bench.hcl
├── scripts/
│   ├── nomad-up
│   ├── nomad-down
│   ├── nomad-reset
│   ├── posix-test-suite.sh
│   ├── setup-local-nfs.sh
│   └── setup-fuse-fallback.sh
└── docs/
    ├── 01-repo-nomad-and-silo-backend/
    ├── 02-plugin-state-and-go-no-go/
    ├── 03-csi-plugin-deployment/
    ├── 04-posix-semantics-tests/
    ├── 05-failure-and-lifecycle-tests/
    ├── 06-fio-performance-comparison/
    ├── 07-fuse-host-volume-fallback/
    └── 08-final-recommendation/
```
