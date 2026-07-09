<#
.SYNOPSIS
    AKS TLS Certificate Expiry Monitor
    Discovers all AKS clusters in the current subscription and scans for
    tls.crt and ca.crt secrets expiring within a configurable threshold (default 30 days).
    Uploads per-cluster JSON reports to Azure Blob Storage.

.DESCRIPTION
    Iterates every AKS cluster in the subscription, authenticates via az/kubelogin,
    then examines every kubernetes.io/tls secret across all namespaces.
    Both the leaf certificate (tls.crt) and any CA certificates (ca.crt) are
    checked against the expiry threshold.

    Uses the Exec function from Common-Utilities.ps1 which wraps external
    commands and throws on non-zero exit codes.

.COMPATIBILITY
    This script is invoked by TWO pipelines:
      1. The isolated nightly TLS pipeline (check-k8s-tls-cert-expiry.yml)
         - Does NOT pass -ClusterNamePattern.
         - Scans every AKS cluster in the subscription.
      2. The unified nightly monitoring pipeline (unified-monitoring.yml)
         - Passes -ClusterNamePattern '^AKSJOMS[A-Za-z]{4}GV01$'.
         - Scans only matching clusters.

    To preserve isolated-pipeline behavior bit-for-bit, -ClusterNamePattern
    defaults to '' (empty). When empty, no filter is applied (scan all).
    When non-empty, the cluster list is filtered via -match.

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
    [int]$ExpiryThresholdDays = 30,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountKey = '',

    [Parameter(Mandatory = $false)]
    [string]$ClusterNamePattern = ''
)

# Dot-source common utility functions (provides Exec alias for external command error checking)
. "$PSScriptRoot/../functions/CommonUtilities.ps1"

$ErrorActionPreference = "Stop"
$ExpirationLimit = (Get-Date).AddDays($ExpiryThresholdDays)
$CurrentDateStr = Get-Date -Format "yyyyMMdd-HHmm"
$TotalFindings = 0
$FailedClusters = @()

# --- 1. Discover all AKS clusters in the subscription ---
Write-Host "`n=========================================="
Write-Host "AKS TLS Certificate Expiry Monitor"
Write-Host "Threshold : $ExpiryThresholdDays days"
if ($ClusterNamePattern) {
    Write-Host "Pattern   : $ClusterNamePattern"
} else {
    Write-Host "Pattern   : (none - scanning all clusters)"
}
Write-Host "Storage   : $StorageAccountName / $ContainerName"
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
        $null = Exec kubelogin convert-kubeconfig -l azurecli

        # Scan all namespaces for TLS secrets
        $namespaceOutput = Exec kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'

        foreach ($ns in (-split $namespaceOutput)) {
            Write-Host "  Checking namespace: $ns"

            $secretOutput = Exec kubectl get secrets -n $ns --field-selector type=kubernetes.io/tls `
                -o jsonpath='{.items[*].metadata.name}'

            foreach ($s in (-split $secretOutput)) {
                Write-Host "    Processing secret: $s"

                # Check both tls.crt and ca.crt if present
                $certKeys = @("tls.crt", "ca.crt")
                foreach ($key in $certKeys) {
                    $certDataB64 = Exec kubectl get secret $s -n $ns -o jsonpath="{.data.$($key.Replace('.', '\.'))}"

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
    if ($ExpiringCerts.Count -gt 0) {
        $TotalFindings += $ExpiringCerts.Count
        $ReportName = "tls_alert_$($C.name)_$CurrentDateStr.json"
        $TempPath = Join-Path $env:TEMP $ReportName

        $ExpiringCerts | ConvertTo-Json -Depth 5 | Set-Content -Path $TempPath -Encoding UTF8

        Write-Host "`n  Uploading $ReportName ($($ExpiringCerts.Count) finding(s)) to storage..."
        $uploadArgs = @(
            '--account-name', $StorageAccountName,
            '--container-name', $ContainerName,
            '--name', "alerts/$ReportName",
            '--file', $TempPath,
            '--overwrite'
        )
        if ($StorageAccountKey) {
            $uploadArgs += '--account-key', $StorageAccountKey
        }
        else {
            $uploadArgs += '--auth-mode', 'login'
        }

        $null = Exec az storage blob upload @uploadArgs
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
