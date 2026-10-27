job "silo" {
  datacenters = ["dc1"]
  type        = "service"

  group "silo" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "nomad-client-1"
    }

    network {
      mode = "host"
      port "s3" {
        static = 9000
      }
      port "console" {
        static = 9001
      }
    }

    volume "silo-data" {
      type      = "host"
      source    = "silo-data"
      read_only = false
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "10s"
      mode     = "fail"
    }

    task "silo" {
      driver = "docker"

      config {
        image        = "docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c"
        network_mode = "host"
        args         = ["server", "/data", "--console-address", ":9001", "--address", ":9000"]
      }

      volume_mount {
        volume      = "silo-data"
        destination = "/data"
        read_only   = false
      }

      template {
        data = <<EOF
MINIO_ROOT_USER="{{ with nomadVar "nomad/jobs/silo" }}{{ .root_user }}{{ end }}"
MINIO_ROOT_PASSWORD="{{ with nomadVar "nomad/jobs/silo" }}{{ .root_password }}{{ end }}"
EOF
        destination = "secrets/silo.env"
        env         = true
        change_mode = "noop"
      }

      service {
        name     = "silo-s3"
        port     = "s3"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/minio/health/live"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
