<#
.SYNOPSIS
    AKS TLS Certificate Expiry Monitor
    Discovers all AKS clusters in the current subscription (optionally filtered
    by regex) and scans for tls.crt and ca.crt secrets expiring within a fixed
    threshold (30 days). Uploads per-cluster JSON reports to Azure Blob Storage
    using the repo's shared AzStorageAccountTools helpers (Save-Blob).

.DESCRIPTION
    Iterates every AKS cluster in the subscription, authenticates via az/kubelogin,
    then examines every kubernetes.io/tls secret across all namespaces.
    Both the leaf certificate (tls.crt) and any CA certificates (ca.crt) are
    checked against the expiry threshold.

    Report upload uses the SAME mechanism as the drift-detection flow:
      New-StorageAccountInfo + Save-Blob
    from scripts/ps/functions/AzStorageAccountTools.ps1. Save-Blob calls
    `az storage blob upload --auth-mode key` (without --account-key), which
    causes Azure CLI to auto-discover the storage account key using the
    logged-in SP's "Microsoft.Storage/storageAccounts/listkeys/action"
    permission. This permission is already granted by the SP's existing
    Reader role on the storage account — NO additional RBAC (Storage Blob
    Data Contributor) is needed.

.AUTHENTICATION PREREQUISITES
    - `az login` must have been performed (Login-AzCli.ps1) so the az CLI
      has a valid token for `az aks list`, `az aks get-credentials`, and
      `az storage blob upload --auth-mode key` (key auto-discovery).

.THRESHOLD POLICY
    The TLS expiry threshold is a FIXED CONSTANT ($ExpiryThresholdDays = 30).
    It is NOT exposed as a script parameter or pipeline parameter.
    To change it, edit the constant below.

.COMPATIBILITY
    This script is invoked by TWO pipelines:
      1. The isolated nightly TLS pipeline (check-k8s-tls-cert-expiry.yml)
         - Does NOT pass -ClusterNamePattern.
         - Scans every AKS cluster in the subscription.
      2. The unified nightly monitoring pipeline (unified-k8s-monitoring.yml)
         - Passes -ClusterNamePattern '^AKSJOMS[A-Za-z]{4}GV01$'.
         - Scans only matching clusters.

    To preserve isolated-pipeline behavior bit-for-bit, -ClusterNamePattern
    defaults to '' (empty). When empty, no filter is applied (scan all).
    When non-empty, the cluster list is filtered via -match.

.PARAMETER StorageAccountName
    Name of the storage account that hosts the alert container.
.PARAMETER ContainerName
    Container name (per-alert-type: e.g. k8s-tls-alert).
.PARAMETER StorageAccountKey
    OPTIONAL. If provided, Save-Blob uses it directly. If omitted (recommended),
    Save-Blob uses --auth-mode key and Azure CLI auto-discovers the key via
    the SP's listkeys permission — same pattern as drift detection.
.PARAMETER ClusterNamePattern
    Optional regex. Only AKS clusters whose name matches are scanned.
    Default: '' (scan every cluster in the subscription).
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountKey = '',

    [Parameter(Mandatory = $false)]
    [string]$ClusterNamePattern = '',

    # Optional: directory containing kubectl.exe and kubelogin.exe.
    # When set (Jenkins case), the script prepends it to $env:Path and
    # rewrites the kubeconfig to reference kubelogin.exe by absolute path
    # — same pattern as Set-AksServerId.ps1. When empty (ADO case), the
    # scripts rely on kubectl/kubelogin already being on PATH (ADO's
    # task.prependpath step handles that).
    [Parameter(Mandatory = $false)]
    [string]$BinDir = ''
)

# Dot-source the repo's shared utility functions:
#   - CommonUtilities.ps1     -> Exec (alias for Invoke-ExternalCommand)
#   - AzStorageAccountTools.ps1 -> New-StorageAccountInfo, Save-Blob
. "$PSScriptRoot/../functions/CommonUtilities.ps1"
. "$PSScriptRoot/../functions/AzStorageAccountTools.ps1"

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# FIXED CONSTANTS — do NOT expose as script parameters or pipeline parameters.
# To change a value, edit it here. Rationale: ADO Server's parameter schema
# does not support type: int, and exposing thresholds as strings invites
# silent typo-driven misconfigurations.
# ---------------------------------------------------------------------------
$ExpiryThresholdDays = 30    # Flag certs expiring within this many days

$ExpirationLimit  = (Get-Date).AddDays($ExpiryThresholdDays)
$CurrentDateStr   = Get-Date -Format "yyyyMMdd-HHmm"
$TotalFindings    = 0
$FailedClusters   = @()

# ---------------------------------------------------------------------------
# Resolve kubectl / kubelogin invocation.
#
# In ADO, the pipeline's `task.prependpath` step puts kubectl.exe and
# kubelogin.exe on PATH, so bare names work.
#
# In Jenkins, the binaries live in $env:WORKSPACE but that directory is NOT
# on PATH by default. Two problems result:
#   1. `kubelogin convert-kubeconfig` writes `kubelogin` (bare name) into
#      the kubeconfig as the exec command for the credential plugin.
#   2. When `kubectl` later invokes that credential plugin, it tries to run
#      `kubelogin` via PATH lookup, fails -> "executable kubelogin not found".
#
# Fix mirrors Set-AksServerId.ps1:
#   - Prepend $BinDir to $env:Path so bare `kubectl`/`kubelogin` resolve.
#   - After `kubelogin convert-kubeconfig`, rewrite the kubeconfig to
#     replace the bare `kubelogin` with the absolute path to kubelogin.exe.
#     This way kubectl's credential-plugin invocation uses the absolute
#     path and doesn't depend on PATH at all.
# ---------------------------------------------------------------------------
$KubectlCmd   = 'kubectl'
$KubeloginCmd = 'kubelogin'
if ($BinDir -and (Test-Path $BinDir)) {
    $env:Path = "$BinDir;$env:Path"
    $KubectlCmd   = Join-Path $BinDir 'kubectl.exe'
    $KubeloginCmd = Join-Path $BinDir 'kubelogin.exe'
    Write-Host "Using tooling from $BinDir (kubectl=$KubectlCmd, kubelogin=$KubeloginCmd)"
}

# Build the StorageAccountInfo object that Save-Blob expects.
# When $StorageAccountKey is empty, Save-Blob falls through to
# `--auth-mode key` without `--account-key`, which triggers Azure CLI's
# built-in key auto-discovery (same path as the drift-detection flow).
if ($StorageAccountKey) {
    $AlertStorageInfo = New-StorageAccountInfo -Name $StorageAccountName -Container $ContainerName -AccountKey $StorageAccountKey
} else {
    $AlertStorageInfo = New-StorageAccountInfo -Name $StorageAccountName -Container $ContainerName
}

# --- 1. Discover all AKS clusters in the subscription ---
Write-Host "`n=========================================="
Write-Host "AKS TLS Certificate Expiry Monitor"
Write-Host "Threshold : $ExpiryThresholdDays days"
if ($ClusterNamePattern) {
    Write-Host "Pattern   : $ClusterNamePattern"
} else {
    Write-Host "Pattern   : (none - scanning all clusters)"
}
Write-Host "Storage   : $StorageAccountName / $ContainerName (auth-mode: key)"
Write-Host "==========================================`n"

Write-Host "Fetching AKS cluster list from subscription..."
$ClusterJsonRaw = Exec az aks list --query "[].{name:name, rg:resourceGroup}" -o json
$ClusterJsonStr = ($ClusterJsonRaw -join "`n")
[array]$AllClusters = ConvertFrom-Json -InputObject $ClusterJsonStr

# Apply pattern filter only when a pattern was supplied. When empty
# (isolated pipeline case), $Clusters = $AllClusters - preserves the
# original "scan everything" behavior.
if ($ClusterNamePattern) {
    [array]$Clusters = $AllClusters | Where-Object { $_.name -match $ClusterNamePattern }
    Write-Host "Found $($AllClusters.Count) AKS cluster(s) in subscription; $($Clusters.Count) match pattern '$ClusterNamePattern'."
} else {
    [array]$Clusters = $AllClusters
    Write-Host "Found $($Clusters.Count) AKS cluster(s) in subscription."
}

if ($Clusters.Count -eq 0) {
    Write-Host "No AKS clusters identified. Exiting cleanly."
    exit 0
}
Write-Host ""

# --- 2. Iterate each cluster ---
foreach ($C in $Clusters) {
    Write-Host "--- Checking Cluster: $($C.name) in RG: $($C.rg) ---"
    $ExpiringCerts = @()

    try {
        # Authenticate to the cluster
        $null = Exec az aks get-credentials --resource-group $C.rg --name $C.name --overwrite-existing

        # Convert kubeconfig to use kubelogin (required for AAD-enabled clusters)
        $null = Exec $KubeloginCmd convert-kubeconfig -l azurecli

        # When $BinDir is set (Jenkins), rewrite the kubeconfig so the
        # credential-plugin exec command references kubelogin.exe by
        # absolute path. Otherwise kubectl's later credential-plugin
        # invocation fails with "executable kubelogin not found" because
        # $BinDir isn't on PATH in the subprocess that runs the plugin.
        # Same pattern as Set-AksServerId.ps1 line 39.
        if ($BinDir -and (Test-Path $BinDir)) {
            $kubeconfigPath = "$env:USERPROFILE/.kube/config"
            if (Test-Path $kubeconfigPath) {
                (Get-Content $kubeconfigPath).Replace('kubelogin', $KubeloginCmd) |
                    Set-Content $kubeconfigPath
            }
        }

        # Scan all namespaces for TLS secrets
        $namespaceOutput = Exec $KubectlCmd get namespaces -o jsonpath='{.items[*].metadata.name}'

        foreach ($ns in (-split $namespaceOutput)) {
            Write-Host "  Checking namespace: $ns"

            $secretOutput = Exec $KubectlCmd get secrets -n $ns --field-selector type=kubernetes.io/tls `
                -o jsonpath='{.items[*].metadata.name}'

            foreach ($s in (-split $secretOutput)) {
                Write-Host "    Processing secret: $s"

                # Check both tls.crt and ca.crt if present
                $certKeys = @("tls.crt", "ca.crt")
                foreach ($key in $certKeys) {
                    $certDataB64 = Exec $KubectlCmd get secret $s -n $ns -o jsonpath="{.data.$($key.Replace('.', '\.'))}"

                    if ($certDataB64) {
                        $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
                            [Convert]::FromBase64String($certDataB64)
                        )
                        $daysRemaining = ($cert.NotAfter - (Get-Date)).Days

                        $status = "Valid"
                        if ($cert.NotAfter -lt (Get-Date)) { $status = "EXPIRED" }
                        elseif ($cert.NotAfter -lt $ExpirationLimit) { $status = "EXPIRING_SOON" }

                        if ($status -ne "Valid") {
                            $ExpiringCerts += [PSCustomObject]@{
                                Cluster       = $C.name
                                ResourceGroup = $C.rg
                                Namespace     = $ns
                                SecretName    = $s
                                CertType      = $key
                                Subject       = $cert.Subject
                                Issuer        = $cert.Issuer
                                ExpiryDate    = $cert.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
                                Status        = $status
                                DaysRemaining = $daysRemaining
                            }

                            $icon = if ($status -eq "EXPIRED") { "[!!]" } else { "[!]" }
                            Write-Host "      $icon $key ($status): $($cert.NotAfter.ToString('yyyy-MM-dd')) (${daysRemaining}d remaining)"
                        }
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
    # Uses Save-Blob from AzStorageAccountTools.ps1 — same helper the drift
    # detection flow uses. When no account key is set on $AlertStorageInfo,
    # Save-Blob runs `az storage blob upload --auth-mode key` (no --account-key)
    # and Azure CLI auto-discovers the key via the SP's listkeys permission.
    if ($ExpiringCerts.Count -gt 0) {
        $TotalFindings += $ExpiringCerts.Count
        $ReportName = "tls_alert_$($C.name)_$CurrentDateStr.json"
        $TempPath = Join-Path $env:TEMP $ReportName

        $ExpiringCerts | ConvertTo-Json -Depth 5 | Set-Content -Path $TempPath -Encoding UTF8

        Write-Host "`n  Uploading $ReportName ($($ExpiringCerts.Count) finding(s)) to storage..."
        Save-Blob `
            -StorageAccountInfo $AlertStorageInfo `
            -BlobName "alerts/$ReportName" `
            -FilePath $TempPath
        Write-Host "  Upload successful: alerts/$ReportName"

        # Clean up temp file
        Remove-Item -Path $TempPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "  No expiring certificates found in cluster $($C.name)."
    }

    Write-Host ""
}

# --- 4. Summary ---
Write-Host "=========================================="
Write-Host "AKS TLS monitoring completed."
Write-Host "Clusters scanned : $($Clusters.Count)"
Write-Host "Clusters failed  : $($FailedClusters.Count)"
Write-Host "Total findings   : $TotalFindings"
Write-Host "=========================================="

if ($TotalFindings -gt 0) {
    Write-Warning "$TotalFindings certificate(s) are expiring or already expired within $ExpiryThresholdDays days."
}

# Per-cluster failures are real errors (auth, kubectl, etc.) - mark step failed
# so on-call gets paged. Finding expiring certs is NOT a failure (alert fires via blob).
if ($FailedClusters.Count -gt 0) {
    Write-Warning "$($FailedClusters.Count) cluster(s) could not be scanned - see log above. Marking step as failed."
    exit 1
}

# Explicit exit 0 so ADO does not fail the task due to caught errors in the error stream
exit 0
