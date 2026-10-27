job "fio-benchmark" {
  datacenters = ["dc1"]
  type        = "batch"

  group "benchmarks" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "nomad-client-1"
    }

    volume "local_ssd" {
      type      = "host"
      source    = "local-ssd-bench"
      read_only = false
    }

    volume "nfs_mount" {
      type      = "host"
      source    = "nfs-bench"
      read_only = false
    }

    volume "silo_csi" {
      type            = "csi"
      source          = "silo-vol-fio"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    task "fio" {
      driver = "docker"

      config {
        image        = "docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e"
        network_mode = "host"
        privileged   = true
        command      = "/bin/sh"
        args         = ["-c", "apk add --no-cache fio bash coreutils >/dev/null && /bin/bash /local/run-bench.sh"]
      }

      volume_mount {
        volume      = "local_ssd"
        destination = "/mnt/local-ssd"
        read_only   = false
      }

      volume_mount {
        volume      = "nfs_mount"
        destination = "/mnt/nfs"
        read_only   = false
      }

      volume_mount {
        volume      = "silo_csi"
        destination = "/mnt/silo-csi"
        read_only   = false
      }

      template {
        data = <<-EOF
#!/bin/bash
set -euo pipefail

echo "======================================================================"
echo "          NOMAD STORAGE NETWORK PERFORMANCE BENCHMARK (FIO)           "
echo "======================================================================"
echo "Targets under evaluation:"
echo "  1. Local Host SSD Volume (/mnt/local-ssd)"
echo "  2. Loopback NFS Volume (/mnt/nfs)"
echo "  3. Silo S3-CSI Volume (/mnt/silo-csi)"
echo ""

run_benchmark() {
  local DIR="$1"
  local NAME="$2"
  echo "----------------------------------------------------------------------"
  echo ">>> BENCHMARKING TARGET: $NAME ($DIR) <<<"
  echo "----------------------------------------------------------------------"
  mkdir -p "$DIR/fio-test"

  echo ">> 1. Sequential Write (128KB, 64MB):"
  fio --name="$NAME-seq-write" --directory="$DIR/fio-test" \
      --rw=write --bs=128k --size=64M --numjobs=1 --time_based=0 \
      --ioengine=sync --group_reporting \
      --output-format=normal

  echo ">> 2. Sequential Read (128KB, 64MB):"
  fio --name="$NAME-seq-read" --directory="$DIR/fio-test" \
      --rw=read --bs=128k --size=64M --numjobs=1 --time_based=0 \
      --ioengine=sync --group_reporting \
      --output-format=normal

  echo ">> 3. Random 4KB Read/Write (4KB, 16MB, 70/30 read/write):"
  fio --name="$NAME-rand-rw" --directory="$DIR/fio-test" \
      --rw=randrw --rwmixread=70 --bs=4k --size=16M --numjobs=1 --time_based=0 \
      --ioengine=sync --group_reporting \
      --output-format=normal

  rm -rf "$DIR/fio-test"
  echo ""
}

run_benchmark "/mnt/local-ssd" "Local-SSD"
run_benchmark "/mnt/nfs" "Loopback-NFS"
run_benchmark "/mnt/silo-csi" "Silo-CSI-S3"

echo "======================================================================"
echo "                   BENCHMARK COMPLETED SUCCESSFULLY                   "
echo "======================================================================"
EOF
        destination = "local/run-bench.sh"
        perms       = "755"
      }

      resources {
        cpu    = 1000
        memory = 512
      }
    }
  }
}
