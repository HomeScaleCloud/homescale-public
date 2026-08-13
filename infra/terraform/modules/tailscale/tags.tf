locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../../../apps", "*/**") : split("/", app_file)[0]
  ]))

  cluster_names = sort(distinct([
    for cluster_file in fileset("${path.module}/../../../../clusters", "*/**") : split("/", cluster_file)[0]
  ]))
}
