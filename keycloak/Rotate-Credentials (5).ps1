<#
.SYNOPSIS
    K8S Management Tools Credential Rotation Script

.DESCRIPTION
    Rotates admin credentials for Rancher, ArgoCD, Keycloak, or Prisma Cloud
    and writes the new password to Azure Key Vault for compliance monitoring.

    Rancher and Prisma Cloud are fully automatic. Keycloak is semi-automatic
    (manual UI rotation + K8s secret sync). ArgoCD is fully automatic via
    secret nullification + deployment restart.
#>
param(
    [Parameter(Mandatory = $true)] [string]$ClusterName,
    [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)] [string]$TargetTool,
    [Parameter(Mandatory = $true)] [string]$KeyVaultName,
    [Parameter(Mandatory = $true)] [string]$BinDir
)

. "$PSScriptRoot/../functions/CommonUtilities.ps1"
$ErrorActionPreference = "Stop"

$env:KUBECONFIG = "$BinDir\kubeconfig"
$env:Path += ";$BinDir"
if (Test-Path $env:KUBECONFIG) {
    Remove-Item $env:KUBECONFIG -Force
}

$toolLower = $TargetTool.ToLower()

Write-Host "`n=========================================="
Write-Host "Standardized Credential Rotation Pipeline"
Write-Host "Cluster   : $ClusterName"
Write-Host "Target    : $toolLower"
Write-Host "Key Vault : $KeyVaultName"
Write-Host "==========================================`n"

Write-Host "Authenticating to AKS cluster $ClusterName..."
$null = Exec az aks get-credentials --resource-group $ResourceGroupName --name $ClusterName --overwrite-existing --format azure
$null = Exec "$BinDir\kubelogin.exe" convert-kubeconfig -l azurecli

(Get-Content $env:KUBECONFIG).Replace('kubelogin', "$BinDir\kubelogin.exe") | `
    Set-Content $env:KUBECONFIG

$newPassword = $null

switch ($toolLower) {
    "rancher" {
        Write-Host "Locating Rancher controller pod..."
        $podOutput = Exec kubectl -n cattle-system get pods -l app=rancher --no-headers
        $podName = ($podOutput -split '\s+')[0]

        if (-not $podName) { throw "Rancher controller pod not found." }

        Write-Host "Executing reset-password inside pod: $podName"
        $rawOutput = Exec kubectl -n cattle-system exec $podName -c rancher -- reset-password

        if ($rawOutput -match "New password for default administrator \(.*\):\s*(.*)") {
            $newPassword = $matches[1].Trim()
        }
        else { throw "Failed to parse Rancher output. Trace: $rawOutput" }
    }
    "argocd" {
        Write-Host "Nullifying active password strings from argocd secrets using JSON patch..."

        $patchJson = @"
[
  {
    "op": "replace",
    "path": "/data/admin.password",
    "value": null
  },
  {
    "op": "replace",
    "path": "/data/admin.passwordMtime",
    "value": null
  }
]
"@

        $null = Exec kubectl patch secret argocd-secret -n argocd --type='json' -p $patchJson

        Write-Host "Executing rollout restart on core-app-argocd-server..."
        $null = Exec kubectl -n argocd rollout restart deployment/core-app-argocd-server
        $null = Exec kubectl -n argocd rollout status deployment/core-app-argocd-server

        Write-Host "Retrieving newly generated password from argocd-initial-admin-secret..."
        $base64Pass = Exec kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"

        if ([string]::IsNullOrEmpty($base64Pass)) {
            throw "ArgoCD initial admin secret password field is empty or failed to auto-regenerate."
        }

        $newPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64Pass)).Trim()
    }
    "keycloak" {
        Write-Host "`n=========================================="
        Write-Host "Keycloak Admin Password Sync (Semi-Automatic)"
        Write-Host "==========================================`n"

        $namespace  = "auth"
        $secretName = "keycloak-admin-password"
        $secretKey  = "keycloak-admin-password"

        Write-Host "Reading admin password from K8s secret '$secretName' in namespace '$namespace'..."
        $b64Pass = Exec kubectl get secret $secretName -n $namespace -o jsonpath="{.data.$secretKey}"

        if ([string]::IsNullOrEmpty($b64Pass)) {
            throw @"
K8s secret '$secretName' (key '$secretKey') not found or empty in namespace '$namespace'.

This pipeline does NOT rotate the Keycloak admin password. The admin must:
  1. Rotate the password via the Keycloak admin UI.
  2. Update the K8s secret '$secretName' in namespace '$namespace' with the new password.
  3. Re-run this pipeline to sync the K8s secret value to Key Vault.
"@
        }

        $newPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Pass)).Trim()
        Write-Host "Admin password retrieved from K8s secret. Syncing to Key Vault..."
    }
    "prisma" {
        Write-Host "`n=========================================="
        Write-Host "Prisma Cloud Admin Password Rotation (Automated)"
        Write-Host "==========================================`n"

        $namespace = "twistlock"
        $consoleApi = "http://localhost:8081/api/v1"

        Write-Host "Reading current admin password from Key Vault..."
        $currentSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "prisma-admin-password" -ErrorAction SilentlyContinue
        if (-not $currentSecret) {
            throw @"
Key Vault secret 'prisma-admin-password' not found in vault '$KeyVaultName'.

For the FIRST rotation, seed the KV with the current admin password:
  az keyvault secret set --vault-name $KeyVaultName --name prisma-admin-password --value '<current-password>'

After seeding, re-run this pipeline. Subsequent rotations are fully automated.
"@
        }
        $currentPassword = $currentSecret.SecretValueText

        Write-Host "Locating Twistlock console pod..."
        $podOutput = Exec kubectl -n $namespace get pods -l "app.kubernetes.io/name=twistlock-console" --no-headers
        $podName = ($podOutput -split '\s+')[0]
        if (-not $podName) { throw "Twistlock console pod not found in namespace '$namespace'." }
        Write-Host "  Console pod: $podName"

        Write-Host "Authenticating to Prisma Cloud API..."
        $authPayload = @{ username = "admin"; password = $currentPassword } | ConvertTo-Json -Compress
        $authPayloadEscaped = $authPayload -replace "'", "'\''"
        $authCmd = "curl -sk -X POST '$consoleApi/authenticate' -H 'Content-Type: application/json' -d '$authPayloadEscaped'"
        $authResult = Exec kubectl -n $namespace exec $podName -- sh -c $authCmd

        $authObj = $authResult | ConvertFrom-Json
        if (-not $authObj.token) { throw "Failed to obtain JWT from Prisma Cloud API. Response: $authResult" }
        $jwt = $authObj.token
        Write-Host "  JWT obtained successfully."

        Write-Host "Retrieving admin user ID..."
        $usersCmd = "curl -sk '$consoleApi/users' -H 'Authorization: Bearer $jwt'"
        $usersResult = Exec kubectl -n $namespace exec $podName -- sh -c $usersCmd

        $users = $usersResult | ConvertFrom-Json
        $adminUser = $users | Where-Object { $_.username -eq "admin" } | Select-Object -First 1
        if (-not $adminUser) { throw "Admin user not found in Prisma Cloud user list. Response: $usersResult" }
        $adminId = $adminUser.id
        $adminRole = $adminUser.role
        Write-Host "  Admin user ID: $adminId"
        Write-Host "  Admin role: $adminRole"

        Write-Host "Generating new STIG-compliant password..."
        $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        $lower = "abcdefghijkmnpqrstuvwxyz"
        $digits = "23456789"
        $special = "!@#$%^&*()-_=+"
        $all = $upper + $lower + $digits + $special
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object 'byte[]' 1
        $chars = @()
        $rng.GetBytes($bytes); $chars += $upper[$bytes[0] % $upper.Length]
        $rng.GetBytes($bytes); $chars += $lower[$bytes[0] % $lower.Length]
        $rng.GetBytes($bytes); $chars += $digits[$bytes[0] % $digits.Length]
        $rng.GetBytes($bytes); $chars += $special[$bytes[0] % $special.Length]
        for ($i = 0; $i -lt 16; $i++) {
            $rng.GetBytes($bytes)
            $chars += $all[$bytes[0] % $all.Length]
        }
        $newPassword = -join ($chars | Sort-Object { Get-Random })
        Write-Host "  New password generated (20 chars, STIG-compliant)."

        Write-Host "Rotating admin password via API..."
        $updatePayload = @{
            id       = $adminId
            username = "admin"
            password = $newPassword
            role     = $adminRole
        } | ConvertTo-Json -Compress
        $updatePayloadEscaped = $updatePayload -replace "'", "'\''"
        $updateCmd = "curl -sk -X PUT '$consoleApi/users/$adminId' -H 'Content-Type: application/json' -H 'Authorization: Bearer $jwt' -d '$updatePayloadEscaped'"
        $updateResult = Exec kubectl -n $namespace exec $podName -- sh -c $updateCmd

        Write-Host "  API response: $updateResult"
        Write-Host "Prisma Cloud admin password rotated successfully."
    }
    default { throw "Unsupported tool specified: $toolLower" }
}

Write-Host "Updating Azure Key Vault secret '$toolLower-admin-password'..."
$SecretValue = ConvertTo-SecureString $newPassword -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$toolLower-admin-password" -SecretValue $SecretValue | Out-Null
Write-Host "Key Vault updated successfully. 60-day STIG compliance clock reset for $toolLower."
exit 0
