locals {
    c1_project_name = (
        var.environment_name == "PP" ? 
        "MVP" :
        upper(var.environment_name)
    )
    c1_base_name = join("",
        [
            "AZ-GV-DOD-AF-CCE-",
            upper(var.functional_area),
            "-",
            upper(substr(var.stage, 0, 1)),
            "-IL5-",
            upper(var.project),
            upper(local.c1_project_name)
        ]
    )
    key_vault_name = join("",
        [
            "GV",
            upper(var.project),
            upper(substr(var.stage, 0, 1)),
            "IL5KV1"
        ]
    )
}
