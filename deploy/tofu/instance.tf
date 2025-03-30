# resource "vultr_instance" "omni" {
#   hostname = "omni.homescale.cloud"
#   plan     = "vc2-1c-2gb"
#   region   = "lhr"
#   os_id    = 2284
#   backups  = "enabled"
#   backups_schedule {
#     type = "daily"
#   }
# }

# resource "vultr_instance" "kmn_lon1_core" {
#   count    = 3
#   hostname = "kmn-${count.index + 1}.prod.lon1.homescale.cloud"
#   plan     = "vc2-2c-4gb"
#   region   = "lhr"
#   os_id    = 2284
#   vpc2_ids = [ vultr_vpc2.lon1_core.id ]
#   backups  = "enabled"
#   backups_schedule {
#     type = "daily"
#   }
# }
