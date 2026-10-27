job "consumer-fuse-fallback" {
  datacenters = ["dc1"]
  type        = "service"

  group "consumer" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "nomad-client-1"
    }

    volume "fallback_vol" {
      type      = "host"
      source    = "fuse-fallback"
      read_only = false
    }

    task "app" {
      driver = "docker"

      config {
        image        = "docker.io/library/alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e"
        network_mode = "host"
        privileged   = true
        command      = "/bin/sh"
        args = [
          "-c",
          <<-EOF
          set -e
          echo "=== Static Host FUSE Fallback Consumer Starting ==="
          ls -la /mnt/fuse-fallback
          echo "Writing test payload from fallback consumer..."
          echo "Payload written via Static Host FUSE Fallback at $(date -u)" > /mnt/fuse-fallback/fallback-consumer-proof.txt
          sync
          echo "Verification readback:"
          cat /mnt/fuse-fallback/fallback-consumer-proof.txt
          tail -f /dev/null
          EOF
        ]
      }

      volume_mount {
        volume      = "fallback_vol"
        destination = "/mnt/fuse-fallback"
        read_only   = false
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
