# AzureNSG_BlockListUpdate
works with ScreenConnect Blocklist and updates a VM's Network Security Group (NSG) with a fresh rule to block in and outbound traffic.\

# Prerequisites
- Powershell7
  - Module Az.Accounts and Az.Network
  - should auto install if not present
- VM Should be hosted in Azure
  - VM should have a single NIC, I doubt multiple interfaces will work
  - VM should have a Managed System ID with a role that has the following permissions (though Network Contributor is just fine)
    ```JSON
    {
      "properties": {        "roleName": "Network Security Group Contributor (FIT)",
      "description": "",
      "assignableScopes": [],
      "permissions": [
         {
            "actions": [
                        "Microsoft.Network/networkSecurityGroups/read",
                        "Microsoft.Network/networkSecurityGroups/securityRules/read",
                        "Microsoft.Network/networkSecurityGroups/securityRules/write",
                        "Microsoft.Network/networkSecurityGroups/securityRules/delete",
                        "Microsoft.Network/networkInterfaces/read",
                        "Microsoft.Network/networkSecurityGroups/write"
                    ],
                    "notActions": [],
                    "dataActions": [],
                    "notDataActions": []
                }
            ]
        }}
    ```
- A Blocklist file containing one IPv4 address on each line

# Usage

```Powershell
UpdateNSG.ps1 -BlockListPath <path to blocklist>
```
with any luck the VM will just work out everything and update the NSG assigned to its network interface card.
