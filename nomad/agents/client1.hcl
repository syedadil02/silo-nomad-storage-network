name       = "nomad-client-1"
datacenter = "dc1"
data_dir   = "/tmp/nomad-lab/client1"
bind_addr  = "127.0.0.1"

advertise {
  http = "127.0.0.1:4646"
  rpc  = "127.0.0.1:4647"
  serf = "127.0.0.1:4648"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
  servers = ["127.0.0.1:4647"]

  host_volume "silo-data" {
    path      = "/tmp/nomad-lab/volumes/silo-data"
    read_only = false
  }

  host_volume "local-ssd-bench" {
    path      = "/tmp/nomad-lab/volumes/local-ssd-bench"
    read_only = false
  }

  host_volume "nfs-bench" {
    path      = "/tmp/nomad-lab/volumes/nfs-mount"
    read_only = false
  }

  host_volume "fuse-fallback" {
    path      = "/tmp/nomad-lab/volumes/fuse-fallback"
    read_only = false
  }
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
