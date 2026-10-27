job "consumer-multi-writer" {
  datacenters = ["dc1"]
  type        = "service"

  group "workers" {
    count = 2

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    volume "shared_vol" {
      type            = "csi"
      source          = "silo-vol-multi"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "multi-node-multi-writer"
    }

    task "worker" {
      driver = "docker"

      config {
        image = "docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e"
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOF
          set -e
          NODE_NAME="${node.unique.name}"
          echo "[Worker $NODE_NAME] Initialized on $NODE_NAME"
          echo "Worker on node $NODE_NAME active at $(date -u)" > "/data/worker-$NODE_NAME.txt"
          sync

          # Allow both workers time to initialize simultaneously
          sleep 2

          # Concurrent append stress: each worker appends 50 lines to the shared file
          echo "[Worker $NODE_NAME] Starting 50 concurrent appends to /data/concurrent-append.log..."
          for i in $(seq 1 50); do
            echo "Node: $NODE_NAME | Write: $i | Time: $(date -u +%T)" >> /data/concurrent-append.log
            usleep 10000 || sleep 0.01
          done
          sync
          echo "[Worker $NODE_NAME] Completed 50 appends."

          tail -f /dev/null
          EOF
        ]
      }

      volume_mount {
        volume      = "shared_vol"
        destination = "/data"
        read_only   = false
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
