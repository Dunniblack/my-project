output "c1_project_name" {
  description = "The Project Name that C1 uses to provision resources."
  value       = local.c1_project_name
}

output "c1_base_name" {
  description = "The Base Name that C1 uses to provision resources."
  value       = local.c1_base_name
}

output "key_vault_name" {
  description = "The Name of the Key Vault to create."
  value       = local.key_vault_name
}
