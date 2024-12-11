locals {
    acr_public = coalesce(
        var.acr_public, 
        try (
            data.terraform_remote_state.az.outputs.acr_public,
            false
        )
    )
}