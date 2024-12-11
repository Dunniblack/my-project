# This script updates the Hosts file on the Bastions with the FQDN for all private DNS zones and AKS private clusters.

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("BST","TFA")]
    [string]$filter_vm = "BST",
    [Parameter(Mandatory = $false)]
    [string]$filter_rg_vm = "APP-RGP-01"
)

Write-Output "Logging into Azure using AAA Managed Identity..."
    
try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity -EnvironmentName "AzureUSGovernment"
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

$global:entries = "`r`n# Private endpoints - BEGIN`r`n"
# Prepare entries to add to hosts file ######################
function Get-HostsFileLines {

    ## Enumerates DNS records from the Private DNS zones. This would include all Private Endpoints, except for AKS cluster.
    $zones = Get-AzPrivateDnsZone

    foreach ($zone in $zones) {
        $zoneIncluded = $false
        Write-Output "Checking Private DNS Zone: $($zone.Name), RGP:$($zone.ResourceGroupName)"
        if ($zone.Name -match 'privatelink.') {
            Write-Output "PrivateLink: $($zone.Name)"
            $records = Get-AzPrivateDnsRecordSet -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -RecordType A

            foreach ($record in $records) {
                Write-Output "A Record: $($record.Name).($record.ZoneName) $($record.Records.Ipv4Address)"
                Write-Output "A Record: $($record.Name).privatelink.($record.ZoneName) $($record.Records.Ipv4Address)"

                $ip = $record.Records.Ipv4Address
                $fqdn1 = $record.Name + "." + $record.ZoneName
                $fqdn2 = ($record.Name + "." + $record.ZoneName).Replace(".privatelink.", ".")

                $fqdn2 = $fqdn2.Replace("vaultcore.azure.net", "vault.usgovcloudapi.net")
                $fqdn2 = $fqdn2.Replace("azurecr.us", "usgovvirginia.data.azurecr.us")

                $entry = "$ip`t$fqdn1`t$fqdn2`t# Private DNS Zone"
                $global:entries += "$entry`r`n"
            }
            $zoneIncluded = $true
        }
        if ( -not $zoneIncluded -and $zone.Name -match 'private.mysql.') {
            Write-Output "MySQL Private IP: $($zone.Name)"
            $records = Get-AzPrivateDnsRecordSet -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -RecordType A

            foreach ($record in $records) {
                Write-Output "A Record: $($record.Name).($record.ZoneName) $($record.Records.Ipv4Address)"

                $ip = $record.Records.Ipv4Address
                $fqdn1 = $record.Name + "." + $record.ZoneName
                $fqdn2 = ($record.Name + "." + $record.ZoneName).Replace(".private.", ".")

                $entry = "$ip`t$fqdn1`t$fqdn2`t# Private DNS Zone"
                $global:entries += "$entry`r`n"
            }
            $zoneIncluded = $true
        }

        $isHostsFileZone = $false
        if ( -not $zoneIncluded ) {
            $tagValue = $zone.Tags["HOSTSFILE"]
            if ("${tagValue}" -ne "") {
                Write-Output "Tag: HOSTSFILE=${tagValue}"
                $isHostsFileZone = $true
            }
        }
        if ($isHostsFileZone -and $zone.Name -notmatch 'privatelink.') {
            Write-Output "Tagged Private DNS Zone: $($zone.Name)"
            # Zone is tagged "HOSTSFILE" but is NOT a privatelink zone
            $records = Get-AzPrivateDnsRecordSet -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -RecordType A

            foreach ($record in $records) {
                Write-Output "A Record: $($record.Name).($record.ZoneName) $($record.Records.Ipv4Address)"

                $ip = $record.Records.Ipv4Address
                $fqdn1 = $record.Name + "." + $record.ZoneName
                $entry = "$ip`t$fqdn1`t# Private DNS Zone"
                #$entry
                $global:entries += "$entry`r`n"
            }
        }
    }

    ## Get Private Endpoints of AKS cluster
    $aks_clusters = Get-AzAksCluster

    foreach ($aks_cluster in $aks_clusters)
    {
        $aks_pep = Get-AzPrivateEndpoint | Where-Object { $_.PrivateLinkServiceConnections[0].PrivateLinkServiceId -like "*$($aks_cluster.Name)*" }
        $aks_nic = Get-AzNetworkInterface -ResourceId $aks_pep.NetworkInterfaces[0].Id
        $aks_ip = $aks_nic.IpConfigurations[0].PrivateIpAddress
        $aks_fqdn1 = $aks_cluster.PrivateFQDN
        $aks_fqdn2 = $aks_cluster.AzurePortalFQDN
        $aks_entry = "$aks_ip`t$aks_fqdn1`t$aks_fqdn2`t# AKS Private IP"
        $global:entries += "$aks_entry`r`n"
    }

    # TODO:FIXME - Fix the below lines
    $ip = "10.130.0.5"
    $fqdn1 = "jomsregistrydev.azurecr.us"

    $entry = "$ip`t$fqdn1`t# Private DNS Zone"
    $global:entries += "$entry`r`n"
}

Get-HostsFileLines
$content_to_add = $global:entries
Write-Output "`r`nContent to be added to hosts file:"
$content_to_add

# Prepare script to run on VMs ##############################
$part1 = @'
$hosts_file = "$env:windir\System32\drivers\etc\hosts"
$backup_dir = "C:\temp\hosts_backup\"

if (!(Test-Path $backup_dir)) { New-Item -ItemType Directory -Path $backup_dir -Force }

# Backup hosts file
Copy-Item $hosts_file "$backup_dir\hosts.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"

#Write-Output "---------------------------------------"
#Write-Output "Original content before clean:"
#Get-Content $hosts_file

# Remove empty lines and existing entries matching "privatelink.", "Private endpoints", or "gvdtic" in hosts file
# Also remove any lines flagged with end-of-line-comments for Private DNS Zone and AKS Privte IP
$content_clean = Get-Content $hosts_file | Where-Object { $_ -notmatch 'privatelink.|Private endpoints|gvdtic|Private DNS Zone|AKS Private IP' -and $_.Trim() -ne '' }

#Write-Output "---------------------------------------"
#Write-Output "Remaining content after clean:"
#$content_clean

$entries = @'

'@

$part2 = "`r`n'@"

$part3 = @'

#Write-Output "---------------------------------------"
#Write-Output "Entries to add:"
#$entries

Write-Output "Overwrite hosts file with added private DNS zones"
$content_clean + $entries | Set-Content $hosts_file -Force

'@

$script = $part1 + $content_to_add + $part2 + $part3
Write-Output "`r`nScript to run on VMs:"
Write-Output $script

# Run scripts on VMs
$vms = Get-AzVM | Where-Object { $_.StorageProfile.OsDisk.OsType -match 'windows' -and $_.Name -match $filter_vm -and $_.ResourceGroupName -match $filter_rg_vm }

foreach ($vm in $vms) {
    Write-Output "Start running script on " $vm.Name
    $result = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptString $script
    $result
    Write-Output "Complete script..."
}
