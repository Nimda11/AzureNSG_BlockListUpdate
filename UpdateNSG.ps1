param(
    [Parameter(Mandatory=$true)]
    [string]$BlocklistPath
)

# Check and install necessary Azure PowerShell modules
$requiredModules = @("Az.Accounts", "Az.Network")
foreach ($moduleName in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $moduleName
}

# Authenticate using Managed Identity
Connect-AzAccount -Identity

# Retrieve VM information via IMDS
$vmInfoUrl = "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
$vmInfoHeaders = @{
    "Metadata" = "true"
}
$vmInfo = Invoke-RestMethod -Uri $vmInfoUrl -Headers $vmInfoHeaders -Method Get

# Extract necessary details
$vmName = $vmInfo.compute.name
$subscriptionId = $vmInfo.compute.subscriptionId
$resourceGroupName = $vmInfo.compute.resourceGroupName

# Set the context to the correct subscription
Set-AzContext -SubscriptionId $subscriptionId

# Retrieve the NIC attached to the VM
$nic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -like "*$vmName*" }
if ($null -eq $nic) {
    Write-Error "NIC for the VM not found."
    exit
}

# Retrieve the NSG attached to the NIC or its subnet
$nsg = $null
if ($nic.NetworkSecurityGroup -ne $null) {
    $nsgName = $nic.NetworkSecurityGroup.Id.Split('/')[-1]
} elseif ($nic.IpConfigurations[0].Subnet.NetworkSecurityGroup -ne $null) {
    $nsgName = $nic.IpConfigurations[0].Subnet.NetworkSecurityGroup.Id.Split('/')[-1]
}

if (-not [string]::IsNullOrWhiteSpace($nsgName)) {
    $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $resourceGroupName
}

if ($null -eq $nsg) {
    Write-Error "NSG not found."
    exit
}

# Load blocklist IPs from file
$blocklistIPs = Get-Content -Path $BlocklistPath -ErrorAction Stop

# Rule names
$ruleNameInbound = "Fail2Ban_BlockList_In"
$ruleNameOutbound = "Fail2Ban_BlockList_Out"

# Check and remove existing rules if they exist
$existingRuleIn = $nsg.SecurityRules | Where-Object { $_.Name -eq $ruleNameInbound }
$existingRuleOut = $nsg.SecurityRules | Where-Object { $_.Name -eq $ruleNameOutbound }
if ($existingRuleIn) {
    $nsg | Remove-AzNetworkSecurityRuleConfig -Name $ruleNameInbound
}
if ($existingRuleOut) {
    $nsg | Remove-AzNetworkSecurityRuleConfig -Name $ruleNameOutbound
}

# Apply the removal of old rules
$nsg | Set-AzNetworkSecurityGroup

# New rule priority
$newPriority = 100 # Adjust based on your NSG's existing rules to avoid conflicts

# Add new rules for the blocklist
$nsg | Add-AzNetworkSecurityRuleConfig -Name $ruleNameInbound -Description "Block inbound based on Fail2Ban blocklist" -Access Deny -Protocol "*" -Direction Inbound -Priority $newPriority -SourceAddressPrefix $blocklistIPs -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "*"
$nsg | Add-AzNetworkSecurityRuleConfig -Name $ruleNameOutbound -Description "Block outbound based on Fail2Ban blocklist" -Access Deny -Protocol "*" -Direction Outbound -Priority ($newPriority + 10) -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix $blocklistIPs -DestinationPortRange "*"

# Apply the new rules to the NSG
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg

Write-Host "NSG updated with new Fail2Ban List"
