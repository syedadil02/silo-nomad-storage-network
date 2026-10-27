id           = "silo-vol-direct"
name         = "silo-vol-direct"
type         = "csi"
plugin_id    = "silo-s3-csi"

capacity_min = "1GiB"
capacity_max = "10GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  endpoint        = "http://127.0.0.1:9000"
  accessKeyID     = "<CSI_ACCESS_KEY>"
  secretAccessKey = "<CSI_SECRET_KEY>"
  region          = ""
}

parameters {
  mounter   = "s3fs"
  bucket    = "nomad-tests"
  usePrefix = "true"
  prefix    = "vol-single-direct"
}
