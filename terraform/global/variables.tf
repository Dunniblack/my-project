data "local_file" "script" {
  filename = "../../scripts/powershell/update-bastion-hosts-file.ps1"
}

resource "azurerm_automation_runbook" "update_bastion_hosts_file" {
  count                   = 1
  name                    = "update-bastion-hosts-file"
  location                = var.location
  resource_group_name     = var.aa_resource_group_name
  automation_account_name = var.automation_account_name
  log_verbose             = "true"
  log_progress            = "true"
  description             = "Runbook to update hosts file on C1 bastion/ADO agent machines."
  runbook_type            = "PowerShell"
  content                 =  data.local_file.script.content
}