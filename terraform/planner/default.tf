locals {
    kubernetes_version = coalesce(
        var.kubernetes_version, 
        try (
            data.terraform_remote_state.az.outputs.kubernetes_version,
            "1.29"
        )
    )
}