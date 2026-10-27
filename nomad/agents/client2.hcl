name       = "nomad-client-2"
datacenter = "dc1"
data_dir   = "/tmp/nomad-lab/client2"
bind_addr  = "127.0.0.1"

ports {
  http = 4656
  rpc  = 4657
  serf = 4658
}

advertise {
  http = "127.0.0.1:4656"
  rpc  = "127.0.0.1:4657"
  serf = "127.0.0.1:4658"
}

client {
  enabled = true
  servers = ["127.0.0.1:4647"]
}

plugin "docker" {
  config {
    endpoint         = "unix:///run/podman/podman.sock"
    allow_privileged = true
    volumes {
      enabled = true
    }
  }
}
