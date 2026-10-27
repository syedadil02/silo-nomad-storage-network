job "csi-s3-controller" {
  datacenters = ["dc1"]
  type        = "service"

  group "controller" {
    count = 1

    task "plugin" {
      driver = "docker"

      config {
        image        = "docker.io/mwantia/nomad-csi-s3-plugin:v1.0.4@sha256:7f3981c168b3ab610a2898167bf6f73be07bc8876ec8e63182a4203a163c004c"
        network_mode = "host"
        privileged   = true
        args = [
          "--endpoint=unix://csi/csi.sock",
          "--nodeid=${node.unique.name}",
          "--config=/secrets/config.yml",
          "--logtostderr",
          "-v=5"
        ]
      }

      csi_plugin {
        id        = "silo-s3-csi"
        type      = "controller"
        mount_dir = "/csi"
      }

      template {
        data        = <<-EOH
        {{ with nomadVar "nomad/jobs/csi-s3-plugin" }}
        aliases:
          - name: silo
            endpoint: http://127.0.0.1:9000
            accessKeyID: {{ .access_key }}
            secretAccessKey: {{ .secret_key }}
            region: ""
        {{ end }}
        EOH
        destination = "secrets/config.yml"
        change_mode = "restart"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
