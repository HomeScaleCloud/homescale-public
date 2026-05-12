resource "rancher2_machine_config_v2" "s_2cpu_4gb" {
  generate_name = "${var.region}-s-2cpu-4gb"
  harvester_config {
    vm_namespace = "prod"
    cpu_count    = "2"
    memory_size  = "4"
    disk_info    = <<EOF
    {
        "disks": [{
            "imageName": "harvester-public/ubuntu-2604-lts",
            "size": 40,
            "bootOrder": 1
        }]
    }
    EOF
    network_info = <<EOF
    {
        "interfaces": [{
            "networkName": "harvester-public/${var.region}-mgmt"
        }]
    }
    EOF
    ssh_user     = "ubuntu"
    user_data    = <<EOF
    package_update: true
    packages:
      - qemu-guest-agent
      - iptables
    runcmd:
      - - systemctl
        - enable
        - '--now'
        - qemu-guest-agent.service
    EOF
  }
}
