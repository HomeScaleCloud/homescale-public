resource "digitalocean_spaces_bucket" "tfstate" {
  name   = "homescale-tfstate"
  region = "lon1"
  acl    = "private"
}

resource "digitalocean_spaces_bucket" "omni" {
  name   = "homescale-omni"
  region = "lon1"
  acl    = "private"
}
