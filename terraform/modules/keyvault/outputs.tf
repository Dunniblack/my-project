output "environment_name" {
  value = var.environment_name
}

output "project" {
  value = var.project
}

output "c1_project_name" {
  value = module.name-map.c1_project_name
}

output "c1_base_name" {
  value = module.name-map.c1_base_name
}
