job "consumer-single-writer" {
  datacenters = ["dc1"]
  type        = "service"

  group "writer" {
    count = 1

    volume "silo_data" {
      type            = "csi"
      source          = "silo-vol-alias"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    task "writer" {
      driver = "docker"

      config {
        image = "docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e"
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOF
          set -e
          echo "Writing test payload to Silo volume..."
          echo "Nomad CSI Silo persistent payload verified at $(date -u)" > /data/csi-message.txt
          echo "Persisted content successfully:"
          cat /data/csi-message.txt
          sync
          tail -f /dev/null
          EOF
        ]
      }

      volume_mount {
        volume      = "silo_data"
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
