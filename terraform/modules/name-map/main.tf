locals {
    c1_project_name = (
        var.environment_name == "PP" ? 
        "MVP" :
        upper(var.environment_name)
    )
    container_registry_name = join("",
        [
            lower(var.project),
            "registry",
            lower(var.stage)
        ]
    )
    key_vault_name = join("",
        [
            "GV",
            upper(var.project),
            upper(var.environment_name),
            upper(substr(var.stage, 0, 1)),
            "IL5KV-1"
        ]
    )
    sadus_storage_account_name = join("",
        [
            "gv",
            lower(var.c1_project),
            lower(var.environment_name),
            lower(substr(var.stage, 0, 1)),
            "il5sadus"
        ]
    )
    disk_encryption_set_name = join("",
        [
            "GV",
            upper(var.project),
            upper(var.environment_name),
            upper(substr(var.stage, 0, 1)),
            "IL5DES01"
        ]
    )
    disk_encryption_set_key_name = join("",
        [
            "GV",
            upper(var.project),
            upper(var.environment_name),
            upper(substr(var.stage, 0, 1)),
            "IL5DES-key01"
        ]
    )
    resource_group_name = join("",
        [
		    "AZ-GV-DOD-AF-CCE-",
		    upper(var.functional_area),
		    "-",
		    upper(substr(var.stage, 0, 1)),
		    "-IL5-",
		    upper(var.project),
            "-",
            upper(var.environment_name),
		    "-AKS-RGP-01"
        ]
    )
    global_resource_group_name = join("",
        [
		    "AZ-GV-DOD-AF-CCE-",
		    upper(var.functional_area),
		    "-",
		    upper(substr(var.stage, 0, 1)),
		    "-IL5-",
		    upper(var.project),
            "-Global-AKS-RGP-01"
        ]
    )
    aks_name = join("",
        [
            "AKS",
            upper(var.project),
            upper(var.environment_name),
            upper(substr(var.stage, 0, 1)),
            "GV01"
        ]
    )
}