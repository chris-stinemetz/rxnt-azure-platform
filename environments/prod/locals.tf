locals {
  unique_suffix = var.name_suffix
  api_image     = "${module.compute.acr_login_server}/${var.api_image_name}:${var.api_image_tag}"
  site_image    = "${module.compute.acr_login_server}/${var.site_image_name}:${var.site_image_tag}"
}
