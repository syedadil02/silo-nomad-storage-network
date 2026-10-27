job "silo-mc-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  group "mc-init" {
    count = 1

    task "mc" {
      driver = "docker"

      config {
        image        = "docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z@sha256:003925ecebdcd659494621de84984f20aac2ca0ce88684ba23bb1e38b8e0db3c"
        network_mode = "host"
        entrypoint   = ["/bin/sh", "-c"]
        args = [
          <<-EOT
          set -e
          echo "=== 1. Setting alias and querying admin info ==="
          for i in $(seq 1 30); do
            if mc alias set local http://127.0.0.1:9000 "$SILO_ROOT_USER" "$SILO_ROOT_PASSWORD" 2>/dev/null; then
              echo "Connected to Silo successfully."
              break
            fi
            sleep 1
          done
          mc admin info local

          echo "=== 2. Creating bucket nomad-tests ==="
          mc mb --ignore-existing local/nomad-tests

          echo "=== 3. Putting and Getting test object ==="
          echo "silo-nomad-verified" > /tmp/test.txt
          mc cp /tmp/test.txt local/nomad-tests/test.txt
          mc cat local/nomad-tests/test.txt

          echo "=== 4. Creating dedicated CSI service account ==="
          if ! mc alias set csi-check http://127.0.0.1:9000 "$CSI_ACCESS_KEY" "$CSI_SECRET_KEY" >/dev/null 2>&1 || ! mc ls csi-check/nomad-tests/ >/dev/null 2>&1; then
            mc admin accesskey create local "$SILO_ROOT_USER" \
              --access-key "$CSI_ACCESS_KEY" \
              --secret-key "$CSI_SECRET_KEY" 2>/dev/null \
            || mc admin user svcacct add local "$SILO_ROOT_USER" \
              --access-key "$CSI_ACCESS_KEY" \
              --secret-key "$CSI_SECRET_KEY"
          fi

          echo "=== 5. Verifying CSI access key ==="
          mc alias set csi-verify http://127.0.0.1:9000 "$CSI_ACCESS_KEY" "$CSI_SECRET_KEY"
          mc ls csi-verify/nomad-tests/
          echo "CSI access key verified successfully."
          EOT
        ]
      }

      template {
        data = <<EOF
SILO_ROOT_USER="{{ with nomadVar "nomad/jobs/silo" }}{{ .root_user }}{{ end }}"
SILO_ROOT_PASSWORD="{{ with nomadVar "nomad/jobs/silo" }}{{ .root_password }}{{ end }}"
CSI_ACCESS_KEY="{{ with nomadVar "nomad/jobs/silo" }}{{ .test_access_key }}{{ end }}"
CSI_SECRET_KEY="{{ with nomadVar "nomad/jobs/silo" }}{{ .test_secret_key }}{{ end }}"
EOF
        destination = "secrets/mc.env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
