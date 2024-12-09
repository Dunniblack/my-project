if ($args[0] -eq "-h") {
  echo 'This script deploys the core infrastructure required to run an AKS cluster in Cloud1.

Usage:

./deploy-aks-cloud1.ps1 <zone> <app-name> <app-num>

Features:
- Encryption at rest via customer-managed key
- Workload isolation (Dedicated hosts)
- Encrypted acr instance, ready to attach to aks cluster'

}

$ErrorActionPreference = "Stop"

#az config set cloud.name=AzureUSGovernment

$account = az account show | ConvertFrom-Json
echo $account
if (! $account) {
  echo "Error: account info could not be retrieved, this usually means that you need to login with:"
  echo ""
  echo "az login"
  exit 1
}

# Set to dev, test, or prod
$zone = "test"
$app = "jomsmvp"
$appNum = "01"

if ($args[0]) {
  $zone = $args[0]
}

if ($args[1]) {
  $app = $args[1]
}

if ($args[2]) {
  $appNum = $args[2]
}

$appCaps = $app.toUpper()
$zoneCaps = $zone.toUpper()
$zonePrefix = $zoneCaps[0]

$aksName = "AKS${appNum}${appCaps}${ZonePrefix}GV"

$acrName = "${app}registry${zone}"
echo "acr name: $acrName"
$keyvaultName = "GV${appCaps}${appNum}${zonePrefix}IL5KVT"
echo "Keyvault name: $keyvaultName"
$diskEncryptionSetName = "GV${appCaps}${appNum}${ZonePrefix}IL5DES"
echo "Disk Encryption Set name: $diskEncryptionSetName"

$groups = az group list | ConvertFrom-Json

$groupAks = $groups | where {$_.name -match 'AZ-GV-DOD-AF-CCE-AFMC-.-[^-]+-[^-]+-AKS-RGP-01$'}
$groupAksName = $groupAks.name
echo "Group name = $groupAksName"

$groupApp = $groups | where {$_.name -match 'AZ-DE-DOD-AF-CCE-AFMC-.-[^-]+-[^-]+-APP-RGP-02$'}
$groupAppName = $groupApp.name
echo "Group name = $groupAppName"

$kubeletName = "JOMSMVP-AKS-KUBELET-IDENTITY"
$kubeIdentity = az identity show -n $kubeletName -g $groupAksName | ConvertFrom-Json
$kubeletId = $kubeIdentity.id
echo "kubelet managed identity = $kubeletName"
echo "kubelet managed identity ID = $kubeletId"

$aksControlPlaneIdentity = "JOMSMVP-AKS-CP-IDENTITY"
$cpIdentity = az identity show -n $aksControlPlaneIdentity -g $groupAksName | ConvertFrom-Json
$cpId = $cpIdentity.id
echo "Control Plane Identity = $aksControlPlaneIdentity"
echo "Control Plane managed identity = $cpId"


# Get the Group that will be used for the AKS RBAC Cluster Admin Role
$aksClusterAdmin = "Contributor-CCE-AFMC-JOMSMVP-APP-${zoneCaps}"
$aksClusterAdminId = az ad group show --group $aksClusterAdmin --query id -o tsv
echo "AKS Cluster Admin Id = $aksClusterAdminId"

#Get the Group that will be used for the AKS RBAC Cluster View Role
$aksClusterView = "ReadOnly-CCE-AFMC-JOMSMVP-APP-${zoneCaps}"
$aksClusterViewId = az ad group show --group $aksClusterView --query id -o tsv
echo "AKS Cluster ReadOnly Id = $aksClusterViewId"

$vnets = az network vnet list --resource-group AZ-GV-DOD-AF-CCE-AFMC-${zonePrefix}-IL5-JOMSMVP-NET-RGP-01 | ConvertFrom-Json
$vnet = $vnets | where {$_.name -match 'AZ-GV-DOD-AF-CCE-AFMC-.-[^-]+-[^-]+-VNT-01$'}
$vnetName = $vnet.name
echo "Vnet name = $vnetName"

$subnetMatch = "AZ-GV-DOD-AF-CCE-AFMC-.-[^-]+-[^-]+-AKS-SNT-${appNum}$"
$subnets = $vnet.subnets
$subnet = $subnets | where {$_.name -match $subnetMatch}
$subnetId = $subnet.id
echo "Subnet ID = $subnetId"

echo "Attempting to create keyvault..."
echo "Running: $keyvault = az keyvault create --location usgovvirginia --name $keyvaultName -g $groupAppName | ConvertFrom-Json"
$keyvault = az keyvault create --location usgovvirginia --name $keyvaultName -g $groupAppName  | ConvertFrom-Json

if (! $keyvault){
  echo "keyvault already created, getting info..."
  $keyvault = az keyvault show --name $keyvaultName -g $groupAppName | ConvertFrom-Json
}

$keyvaultName = $keyvault.name

az keyvault update -g $groupAppName -n $keyvaultName --enable-purge-protection true

echo "Checking to see if an AKS encryption key already exists..."
$key = az keyvault key show -n "${aksName}-key" --vault-name $keyvaultName | ConvertFrom-Json

if (! $key) {
  echo "AKS encryption key not found, creating now..."
  $key = az keyvault key create -n "${aksName}-key" --vault-name $keyvaultName| ConvertFrom-Json
}

echo "Checking to see if an AKS disk encryption set already exists..."
$diskEncryptionSet = az disk-encryption-set show --name $diskEncryptionSetName -g $groupAKSName | ConvertFrom-Json

if (! $diskEncryptionSet) {
  echo "disk encryption set not found, creating now..."
  $diskEncryptionSet = az disk-encryption-set create --location usgovvirginia --name $diskEncryptionSetName -g $groupAksName --key-url $key.key.kid --source-vault $keyvaultName | ConvertFrom-Json
}

az keyvault set-policy -n $keyvaultName --key-permissions get wrapKey unwrapKey --object-id $diskEncryptionSet.identity.principalId

echo "Checking to see if a Host Group already exists..."
$hostGroup = az vm host group list | ConvertFrom-Json

if (! $hostGroup) {
  echo "Host Group not found, creating now..." 
  $hostGroup = az vm host group create --name HGP01JOMSMVP02TGV -g $groupAksName --platform-fault-domain-count 1 --automatic-placement true | ConvertFrom-Json
}

$hostGroupId = $hostGroup.id

echo "Checking to see if Dedicated Host already exists..."
$dedicatedHost = az vm host list --host-group $hostGroup.name -g $groupAksName | ConvertFrom-Json

if (! $dedicatedHost) {
  echo "Dedicated Host not found, creating now..."
  $dedicatedHost = az vm host create --host-group $hostGroup.name --name DHT01JOMSMVPTGV --sku Ddsv4-Type1 --platform-fault-domain 0 -g $groupAksName
}

echo "Attempting to create aks cluster..."
az aks create -g $groupAksName -n $aksName --enable-aad --enable-blob-driver --assign-identity $cpId --assign-kubelet-identity $kubeletid --aad-admin-group-object-ids $aksClusterAdminId --vnet-subnet-id $subnetId --network-plugin azure --network-plugin-mode overlay --network-dataplane cilium --enable-encryption-at-host --node-osdisk-diskencryptionset-id $diskEncryptionSet.id --kubernetes-version 1.27.7 --host-group-id $hostGroupId  --node-count 4 --max-pods 125 --node-vm-size standard_D16ds_v4 --generate-ssh-keys --location usgovvirginia


if (! $aksCluster) {
  echo "aks cluster already created, getting info..."
  $aksCluster = az aks show -g $groupAksName -n $aksName
}

echo "Attempting to create the acr identity..."
$identity = az identity create -n "${acrName}-identity" -g $groupAppName | ConvertFrom-Json

if (! $identity) {
  echo "acr identity already created, getting info..."
  $identity = az identity show -n "${acrName}-identity" -g $groupAppName | ConvertFrom-Json
}

az keyvault set-policy -g $groupAppName -n $keyvaultName --key-permissions get unwrapKey wrapKey --object-id $identity.principalId

echo "Attempting to create acr encryption key..."
$acrKey = az keyvault key create -n "${acrName}-encryption-key" --vault-name $keyvaultName | ConvertFrom-Json

if (! $acrKey) {
  echo "acr encryption key already created, getting info..."
  $acrKey = az keyvault key show -n "${acrName}-encryption-key" --vault-name $keyvaultName | ConvertFrom-Json
}

echo "Attempting to create the acr..."
$acr = az acr create -n $acrName -g $groupAppName --sku premium --location usgovvirginia --identity $identity.id --key-encryption-key $acrKey.key.kid | ConvertFrom-Json

if (! $acr) {
  echo "acr already created, getting info..."
  $acr = az acr show -n $acrName -g $groupAppName | ConvertFrom-Json
}

$acrName = $acr.Name

# Make the acr reachable on the existing network/subnet
$vnets = az network vnet list | ConvertFrom-Json
$vnet = $vnets | where {$_.name -match 'AZ-DE-DOD-AF-CCE-AFMC-.-[^-]+-[^-]+-VNT-01$'}
$subnet = $vnet.subnets | where {$_.name -match 'CMN-SNT'}
$subnetName = $subnet.name
az network vnet subnet update -g $vnet.resourceGroup --name $subnet.name --vnet-name $vnet.name --disable-private-endpoint-network-policies

echo "Attempting to create the acr endpoint..."
$acrEndpoint = az network private-endpoint create -n "$acrName-endpoint" -g $vnet.resourceGroup --vnet-name $vnet.name --subnet $subnet.name --private-connection-resource-id $acr.id --group-id registry --connection-name "${acrName}-connection" | ConvertFrom-Json

if (! $acrEndpoint) {
  $acrEndpoint = az network private-endpoint show -n "${acrName}-endpoint" -g $vnet.resourceGroup | ConvertFrom-Json  
}

$endpointNic = az network nic show --ids $acrEndpoint.networkInterfaces[0].id | ConvertFrom-Json  

echo "Add the following entries to your machines' hostfiles (/etc/hosts) that you will be using to transfer images images into the acr:"
foreach ($ipConfig in $endpointNic.ipConfigurations) {
  $privateIp = $ipConfig.privateIpAddress
  $fqdn = $ipConfig.privateLinkConnectionProperties.fqdns[0]
  echo "$privateIp $fqdn"
}

# Add acr credentials to the aks keyvault
az acr update -n $acrName --admin-enabled true
$acrCred = az acr credential show -n $acrName | ConvertFrom-Json
$result = az keyvault secret set --vault-name $keyvault.name -n acr-user --value $acrCred.username
$result = az keyvault secret set --vault-name $keyvault.name -n acr-password1 --value $acrCred.passwords[0].value
$result = az keyvault secret set --vault-name $keyvault.name -n acr-password2 --value $acrCred.passwords[1].value

# Create the View Rolebinding for the new cluster
az aks get-credentials --resource-group $groupAksName --name $aksName
kubelogin convert-kubeconfig -l azurecli

kubectl create clusterrolebinding aks-view-binding-aad --clusterrole=view --group=$aksClusterViewId
