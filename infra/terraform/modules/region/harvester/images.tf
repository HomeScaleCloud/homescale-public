resource "harvester_image" "ubuntu_2604_lts" {
  name      = "ubuntu-2604-lts"
  namespace = "harvester-public"

  display_name = "ubuntu-2604-lts.img"
  source_type  = "download"
  url          = "https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img"
}
