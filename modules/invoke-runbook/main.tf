resource "null_resource" "invoke_runbook_pre_des" {
 count = var.environment_name == "C1" ? 1 : 0

 depends_on = [
   var.acr_private_endpoint_id,
   var.acr_private_dns_link_id,
   var.kv_private_endpoint_id,
   var.kv_private_dns_link_id
 ]

 provisioner "local-exec" {
   command = <<EOT
     az automation runbook start \
     --automation-account-name '${var.automation_account_name}' \
     --name '${var.runbook_name}' \
     --resource-group '${var.resource_group_name}' \
     --wait
   EOT
 }
}

resource "null_resource" "invoke_runbook_post_aks" {
 count = var.environment_name == "C1" ? 1 : 0

 depends_on = [
   var.disk_encryption_set_id,
   var.aks_cluster_id
 ]

 provisioner "local-exec" {
   command = <<EOT
     az automation runbook start \
     --automation-account-name '${var.automation_account_name}' \
     --name '${var.runbook_name}' \
     --resource-group '${var.resource_group_name}' \
     --wait
   EOT
 }
}