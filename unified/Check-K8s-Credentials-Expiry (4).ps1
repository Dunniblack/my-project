<#
.SYNOPSIS
    STIG 60-Day Credential Expiry Monitor

.DESCRIPTION
    Discovers all AKS clusters in the current subscription whose name matches
    a configurable regex (default: ^AKSJOMS[A-Za-z]{4}GV01$), and for each one:

      1. Extracts the 4-letter workspace ID from the cluster name (the 4 chars
         immediately after 'AKSJOMS'). For cluster AKSJOMSMVPDGV01 this is 'MVPD'.
      2. Locates the Key Vault in the cluster's own resource group whose name
         starts with 'GVJOMS' + that workspace ID (e.g. 'GVJOMSMVPD'). This is
         the KV where Rotate-Credentials.ps1 writes rotated secrets.
         NOTE: We CANNOT use starts_with(name, 'GVJOMS') alone, because multiple
         clusters can share a resource group, each with its own KV starting with
         'GVJOMS'. The workspace ID disambiguates.
      3. For every tracked credential (rancher-admin-password, etc.), checks
         the rotated secret's age in that KV via `az keyvault secret show`.
      4. If the secret is not yet in KV (initial pre-rotation state), falls
         back to checking the creation age of the underlying K8s deployment.

    Findings at or beyond the warning threshold are uploaded as a per-cluster
    JSON report to Azure Blob Storage, which triggers an Azure Monitor alert.

.AUTHENTICATION
    All Azure operations (az aks list, az keyvault list, az keyvault secret show,
    az storage blob upload) use the az CLI's current login context. The pipeline
    does `az login` in the gather-dynamic-vars stage AND re-runs Login-AzCli.ps1
    at the start of the monitoring job, so the auth context is always fresh.

    Storage blob uploads ALWAYS use --auth-mode login. The SP must have
    "Storage Blob Data Contributor" RBAC on the global storage account. There
    is NO fallback to --account-key — key-based auth has been fully removed.

.THRESHOLD POLICY
    The credential warning threshold is a FIXED CONSTANT ($WarningThresholdDays = 55).
    STIG mandates a 60-day hard limit; 55 days gives a 5-day lead time for
    remediation before STIG non-compliance kicks in.
    This value is NOT exposed as a script parameter or pipeline parameter.
    To change it, edit the variable declaration below.

.PARAMETER StorageAccountName
    Name of the storage account that hosts the alert container.
.PARAMETER ContainerName
    Container name (per-alert-type: e.g. k8s-credentials-alerts).
.PARAMETER ClusterNamePattern
    Regex applied to AKS cluster names. Only matching clusters are scanned.
    Default: ^AKSJOMS[A-Za-z]{4}GV01$
    The 4-letter capture group ([A-Za-z]{4}) is used to derive the KV prefix.
#>

param(
    [Parameter(Mandatory = $true)]  [string]$StorageAccountName,
    [Parameter(Mandatory = $true)]  [string]$ContainerName,
    [Parameter(Mandatory = $false)] [string]$ClusterNamePattern = '^AKSJOMS[A-Za-z]{4}GV01$'
)

. "$PSScriptRoot/../functions/CommonUtilities.ps1"
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# FIXED CONSTANTS — do NOT expose as script parameters or pipeline parameters.
# To change a value, edit it here. Rationale: ADO Server's parameter schema
# does not support type: int, and exposing thresholds as strings invites
# silent typo-driven misconfigurations.
# ---------------------------------------------------------------------------
$WarningThresholdDays = 55    # STIG 60-day hard limit; 5-day lead time
$StigHardLimitDays    = 60    # >= this = EXPIRED (STIG non-compliance)
$KvNameBasePrefix     = 'GVJOMS'  # KV names look like GVJOMS{workspaceId}IL5KV0001

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
Write-Host "KV prefix : $KvNameBasePrefix{workspaceId}*"
Write-Host "Threshold : $WarningThresholdDays days (warn) / $StigHardLimitDays days (expired)"
Write-Host "Storage   : $StorageAccountName / $ContainerName (auth-mode: login)"
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
        # --- 2a. Extract the 4-letter workspace ID from the cluster name ---
        # Cluster format: AKSJOMS{XXXX}GV01 -> XXXX is the workspace ID.
        # KV format:      GVJOMS{XXXX}IL5KV0001 -> same XXXX after GVJOMS.
        #
        # We CANNOT use starts_with(name, 'GVJOMS') alone because multiple
        # clusters can share a resource group, each with its own GVJOMS* KV.
        # The workspace ID disambiguates which KV belongs to which cluster.
        if ($C.name -notmatch '^AKSJOMS([A-Za-z]{4})') {
            throw "Cluster name '$($C.name)' does not match expected pattern 'AKSJOMS{4-letters}...'. Cannot extract workspace ID for KV lookup."
        }
        $WorkspaceId  = $Matches[1]
        $KvNamePrefix = "$KvNameBasePrefix$WorkspaceId"
        Write-Host "  Cluster workspace ID: $WorkspaceId -> KV prefix: $KvNamePrefix"

        # --- 2b. Locate the rotated-credentials KV in this cluster's RG ---
        $kvNameRaw = Exec az keyvault list --resource-group $C.rg `
            --query "[?starts_with(name, '$KvNamePrefix')].name" -o tsv
        $KeyVaultName = ($kvNameRaw -split "`n" | Where-Object { $_ } | Select-Object -First 1)

        if (-not $KeyVaultName) {
            throw "No Key Vault with name starting with '$KvNamePrefix' found in resource group '$($C.rg)' for cluster $($C.name)."
        }
        Write-Host "  Using Key Vault: $KeyVaultName"

        # --- 2c. Authenticate to AKS for deployment-age fallback ---
        $null = Exec az aks get-credentials --resource-group $C.rg --name $C.name --overwrite-existing
        $null = Exec kubelogin convert-kubeconfig -l azurecli

        # --- 2d. Check each tracked secret ---
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
                        WorkspaceId   = $WorkspaceId
                        SecretName    = $secretName
                        AgeDays       = $ageDays
                        Source        = $source
                        Status        = if ($ageDays -ge $StigHardLimitDays) { "EXPIRED" } else { "EXPIRING_SOON" }
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
    # ALWAYS uses --auth-mode login. The SP must have "Storage Blob Data
    # Contributor" RBAC on the storage account. There is NO key-based fallback.
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
            '--overwrite',
            '--auth-mode',      'login'
        )

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
