## SYNOPSIS
Remove Windows 365 licenses if a cloud PC is not used anymore.

## DESCRIPTION
This script will revoke licenses from users that have not used their Windows 365 Cloud PC for a certain amount of days. By default, it will run in simulation mode to notify you of the changes you want to make. Disable simulation mode to actually remove the users from the group. By default, it will only check to remove a license if the cloud PC is not used for more than 30 days. You can change this value by providing the `-daysSinceLastConnection` parameter. Make sure to register an app in Azure AD and give it these Graph Permissions:
- `DeviceManagementManagedDevices.Read.All`
- `GroupMember.ReadWrite.All`
- `CloudPC.Read.All`

## PARAMETERS

### `$app_id`
Provide the app ID of the Entra AD app that has the required permissions.

### `$app_secret`
Provide the app secret of the Entra AD app that has the required permissions.

### `$tenantId`
Provide the tenant ID of the tenant where the app is registered.

## INPUTS
None

## OUTPUTS
Output is written to console.

## NOTES
- **Version:** 1.0
- **Author:** Dieter Kempeneers
- **Creation Date:** 2024-07-14
- **Purpose/Change:** Initial script development

## EXAMPLES

### Run in simulation mode with default parameters
```powershell
.\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>"
```

### Run in simulation mode with another amount of days since last connection
```powershell
.\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -daysSinceLastConnection 60
```
### Run the script to actually remove the users from the group
```powershell
.\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -simulationMode $false
```
### Run the script to actually remove the users from the group with another amount of days since last connection
```powershell
.\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -simulationMode $false -daysSinceLastConnection 60
```


