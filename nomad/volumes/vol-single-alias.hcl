id           = "silo-vol-alias"
name         = "silo-vol-alias"
type         = "csi"
plugin_id    = "silo-s3-csi"

capacity_min = "1GiB"
capacity_max = "10GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  alias = "silo"
}

parameters {
  mounter   = "s3fs"
  bucket    = "nomad-tests"
  usePrefix = "true"
  prefix    = "vol-single-alias"
}
