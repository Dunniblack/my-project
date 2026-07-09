<#
.SYNOPSIS
    STIG 60-Day Credential Expiry Monitor

.DESCRIPTION
    Discovers all AKS clusters in the current subscription whose name matches
    a configurable regex (default: ^AKSJOMS[A-Za-z]{4}GV01$), and for each one:

      1. Locates the Key Vault in the cluster's own resource group whose name
         starts with the configured prefix (default: GVJOMS). This is the KV
         where Rotate-Credentials.ps1 writes rotated secrets.
      2. For every tracked credential (rancher-admin-password, etc.), checks
         the rotated secret's age in that KV via `az keyvault secret show`.
      3. If the secret is not yet in KV (initial pre-rotation state), falls
         back to checking the creation age of the underlying K8s deployment.

    Findings at or beyond the warning threshold are uploaded as a per-cluster
    JSON report to Azure Blob Storage, which triggers an Azure Monitor alert.

    WHY THIS SHAPE
    - Cluster discovery via `az aks list` + regex, NOT via terraform state.
      The global terraform state does NOT expose aks_cluster_name / rg outputs;
      trying to read them there is what caused the previous failure.
    - Per-cluster KV discovery: `az keyvault list --resource-group <rg>` +
      `starts_with(name, 'GVJOMS')`. No hardcoded KV name template.
    - KV access via `az keyvault secret show` (NOT Get-AzKeyVaultSecret).
      The pipeline authenticates via `az login` / Login-AzCli.ps1; there is
      no Connect-AzAccount session, so Get-AzKeyVaultSecret would have failed
      at runtime on every cluster.
    - Per-cluster try/catch: one cluster failing does not abort the run.

.PARAMETER StorageAccountName
    Name of the storage account that hosts the alert container.
.PARAMETER ContainerName
    Container name (per-alert-type: e.g. k8s-credentials-alerts).
.PARAMETER StorageAccountKey
    Optional storage account key. If omitted, az cli falls back to --auth-mode login.
.PARAMETER ClusterNamePattern
    Regex applied to AKS cluster names. Only matching clusters are scanned.
    Default: ^AKSJOMS[A-Za-z]{4}GV01$
.PARAMETER KeyVaultNamePrefix
    KV name prefix used to locate the rotated-credentials KV inside each
    cluster's resource group. Default: GVJOMS
.PARAMETER WarningThresholdDays
    Credentials aged >= this many days are flagged as EXPIRING_SOON (>= 60
    days = EXPIRED). Default: 55 (gives ~5 days lead time before STIG 60-day
    hard limit).
#>

param(
    [Parameter(Mandatory = $true)]  [string]$StorageAccountName,
    [Parameter(Mandatory = $true)]  [string]$ContainerName,
    [Parameter(Mandatory = $false)] [string]$StorageAccountKey          = '',
    [Parameter(Mandatory = $false)] [string]$ClusterNamePattern         = '^AKSJOMS[A-Za-z]{4}GV01$',
    [Parameter(Mandatory = $false)] [string]$KeyVaultNamePrefix         = 'GVJOMS',
    [Parameter(Mandatory = $false)] [int]   $WarningThresholdDays       = 55
)

. "$PSScriptRoot/../functions/CommonUtilities.ps1"
$ErrorActionPreference = "Stop"

$CurrentDateStr = Get-Date -Format "yyyyMMdd-HHmm"
$TotalFindings  = 0
$FailedClusters = @()

# Map tracked secrets to their core deployments. Used for the deployment-age
# fallback when a credential has not yet been rotated into Key Vault.
#
# Add a new entry here when a new tool's rotation SOP lands. The secret name
# MUST match the name written by Rotate-Credentials.ps1 for that tool.
$trackedSecrets = @{
    "rancher-admin-password"  = @{ Namespace = "cattle-system"; Deployment = "core-app-rancher" }
    "argocd-admin-password"   = @{ Namespace = "argocd";        Deployment = "core-app-argocd-server" }
    "keycloak-admin-password" = @{ Namespace = "keycloak";      Deployment = "core-app-keycloak" }
}

# --- 1. Discover all AKS clusters in the subscription and filter by pattern ---
Write-Host "`n=========================================="
Write-Host "STIG 60-Day Credential Expiry Monitor"
Write-Host "Pattern   : $ClusterNamePattern"
Write-Host "KV prefix : $KeyVaultNamePrefix*"
Write-Host "Threshold : $WarningThresholdDays days (warn) / 60 days (expired)"
Write-Host "Storage   : $StorageAccountName / $ContainerName"
Write-Host "==========================================`n"

Write-Host "Fetching AKS cluster list from subscription..."
$ClusterJsonRaw = Exec az aks list --query "[].{name:name, rg:resourceGroup}" -o json
$ClusterJsonStr = ($ClusterJsonRaw -join "`n")
[array]$AllClusters = ConvertFrom-Json -InputObject $ClusterJsonStr

[array]$Clusters = $AllClusters | Where-Object { $_.name -match $ClusterNamePattern }

Write-Host "Found $($AllClusters.Count) AKS cluster(s) in subscription; $($Clusters.Count) match pattern '$ClusterNamePattern'."

if ($Clusters.Count -eq 0) {
    Write-Host "No matching clusters. Exiting cleanly."
    exit 0
}
Write-Host ""

# --- 2. Iterate each matching cluster ---
foreach ($C in $Clusters) {
    Write-Host "--- Checking Cluster: $($C.name) in RG: $($C.rg) ---"
    $ExpiringCreds = @()

    try {
        # --- 2a. Locate the rotated-credentials KV in this cluster's RG ---
        # JMESPath starts_with is case-sensitive; prefix is uppercase 'GVJOMS'
        # to match the deployment-time naming convention.
        $kvNameRaw = Exec az keyvault list --resource-group $C.rg `
            --query "[?starts_with(name, '$KeyVaultNamePrefix')].name" -o tsv
        $KeyVaultName = ($kvNameRaw -split "`n" | Where-Object { $_ } | Select-Object -First 1)

        if (-not $KeyVaultName) {
            throw "No Key Vault with name starting with '$KeyVaultNamePrefix' found in resource group '$($C.rg)'."
        }
        Write-Host "  Using Key Vault: $KeyVaultName"

        # --- 2b. Authenticate to AKS for deployment-age fallback ---
        $null = Exec az aks get-credentials --resource-group $C.rg --name $C.name --overwrite-existing
        $null = Exec kubelogin convert-kubeconfig -l azurecli

        # --- 2c. Check each tracked secret ---
        foreach ($secretName in $trackedSecrets.Keys) {
            $ageDays = $null
            $source  = ""

            try {
                # 1. Attempt to fetch from Key Vault (post-rotation state) via az CLI.
                #    The pipeline authenticates via az cli (Login-AzCli.ps1), NOT
                #    Connect-AzAccount, so we use `az keyvault secret show` instead
                #    of Get-AzKeyVaultSecret.
                $secretJson = Exec az keyvault secret show --vault-name $KeyVaultName --name $secretName -o json
                $secretObj  = $secretJson | ConvertFrom-Json
                $updated    = [datetime]$secretObj.attributes.updated
                $ageDays    = (New-TimeSpan -Start $updated -End (Get-Date)).Days
                $source     = "Azure Key Vault"
            }
            catch {
                # 2. Secret not in KV (initial pre-rotation state): fall back to
                #    the deployment creation age.
                Write-Host "  [INFO] $secretName not found in KV $KeyVaultName. Checking initial deployment age via kubectl..."

                $ns     = $trackedSecrets[$secretName].Namespace
                $deploy = $trackedSecrets[$secretName].Deployment

                try {
                    $creationTimeStr = Exec kubectl get deployment $deploy -n $ns -o jsonpath='{.metadata.creationTimestamp}'

                    if (-not [string]::IsNullOrWhiteSpace($creationTimeStr)) {
                        $creationTimeStr = $creationTimeStr -replace "'", ""
                        $creationDate    = [datetime]$creationTimeStr
                        $ageDays         = (New-TimeSpan -Start $creationDate -End (Get-Date)).Days
                        $source          = "Cluster Deployment ($deploy)"
                    }
                    else {
                        Write-Warning "  [WARN] Could not retrieve creation timestamp for deployment '$deploy' in namespace '$ns'."
                    }
                }
                catch {
                    Write-Warning "  [WARN] Failed to query kubectl for '$deploy' in namespace '$ns'. Is the tool deployed?"
                }
            }

            if ($null -ne $ageDays) {
                Write-Host "  Secret: $secretName | Age: $ageDays Days | Source: $source"

                if ($ageDays -ge $WarningThresholdDays) {
                    $ExpiringCreds += [PSCustomObject]@{
                        Cluster       = $C.name
                        ResourceGroup = $C.rg
                        KeyVault      = $KeyVaultName
                        SecretName    = $secretName
                        AgeDays       = $ageDays
                        Source        = $source
                        Status        = if ($ageDays -ge 60) { "EXPIRED" } else { "EXPIRING_SOON" }
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "  [ERROR] Failed to scan cluster $($C.name): $($_.Exception.Message)"
        $FailedClusters += [PSCustomObject]@{
            Cluster       = $C.name
            ResourceGroup = $C.rg
            Error         = $_.Exception.Message
        }
        continue
    }

    # --- 3. Upload per-cluster report if findings exist ---
    if ($ExpiringCreds.Count -gt 0) {
        $TotalFindings += $ExpiringCreds.Count
        $ReportName = "credential_alert_$($C.name)_$CurrentDateStr.json"
        $TempPath   = Join-Path $env:TEMP $ReportName

        $ExpiringCreds | ConvertTo-Json -Depth 5 | Set-Content -Path $TempPath -Encoding UTF8

        Write-Host "`n  Uploading $ReportName ($($ExpiringCreds.Count) finding(s)) to storage..."
        $uploadArgs = @(
            '--account-name',   $StorageAccountName,
            '--container-name', $ContainerName,
            '--name',           "alerts/$ReportName",
            '--file',           $TempPath,
            '--overwrite'
        )
        if ($StorageAccountKey) { $uploadArgs += '--account-key', $StorageAccountKey }
        else                     { $uploadArgs += '--auth-mode',   'login' }

        $null = Exec az storage blob upload @uploadArgs
        Write-Host "  Upload successful: alerts/$ReportName"

        Remove-Item -Path $TempPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "  All tracked credentials within threshold for cluster $($C.name)."
    }

    Write-Host ""
}

# --- 4. Summary ---
Write-Host "=========================================="
Write-Host "Credential expiry monitoring completed."
Write-Host "Clusters scanned : $($Clusters.Count)"
Write-Host "Clusters failed  : $($FailedClusters.Count)"
Write-Host "Total findings   : $TotalFindings"
Write-Host "=========================================="

if ($TotalFindings -gt 0) {
    Write-Warning "$TotalFindings credential(s) at or beyond $WarningThresholdDays-day warning threshold."
}

if ($FailedClusters.Count -gt 0) {
    Write-Warning "$($FailedClusters.Count) cluster(s) could not be scanned - see log above. Marking step as failed."
    exit 1
}

exit 0
