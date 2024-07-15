## SYNOPSIS
Remove Windows 365 licenses if a cloud PC is not used anymore.

## DESCRIPTION
This script will revoke licenses from users that have not used their Windows 365 Cloud PC for a certain amount of days. By default, it will run in simulation mode to notify you of the changes you want to make. Disable simulation mode to actually remove the users from the group. By default, it will only check to remove a license if the cloud PC is not used for more than 30 days. You can change this value by providing the `-daysSinceLastConnection` parameter. 

This script does not work if the license is assigned directly to a user.

## REQUIREMENTS
Make sure to register an app in Entra ID and give it these Graph Permissions:
- `DeviceManagementManagedDevices.Read.All` (To device identifiers from Intune)
- `GroupMember.ReadWrite.All` (To read and remove the groupmembership where the license is assigned)
- `CloudPC.Read.All` (To fetch the last connection date from the Cloud PCs)

It also requires permissions on Entra ID as well:
- Create a custom role : `microsoft.directory/groups/members/read`

- **OR** use athe built in role: `Directory Readers`

## PARAMETERS

### `$app_id`
Provide the app ID of the Entra AD app that has the required permissions.

### `$app_secret`
Provide the app secret of the Entra AD app that has the required permissions.

### `$tenantId`
Provide the tenant ID of the tenant where the app is registered.

### `$daysSinceLastConnection`
provide the amount of days since the last connection of the cloud pc to revoke the license, default is 30

### `$simulationMode`
provide if the script should run in simulation mode or not, default is true

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


