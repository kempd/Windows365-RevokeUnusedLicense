
<#
.SYNOPSIS
  Remove Windows 365 licenses if a cloud pc is not used anymore
.DESCRIPTION
  This script will revoke licenses from users that have not used their Windows 365 Cloud PC for a certain amount of days.
  By default it will in simulation mode to notify you of the changes you want to make. Disable simulation mode to actually remove the users from the group.
  By default it will only check to premove a license if the cloud pc is not used for more than 30 days. You can change this value by providing the -daysSinceLastConnection parameter.
  Make sure to register an app in Azure AD and give it these Graph Permissions:
    DeviceManagementManagedDevices.Read.All,
    GroupMember.ReadWrite.All	
    CloudPC.Read.All
  Add the following Entra ID role as well:
    Directory Readers
.PARAMETER $app_id
    provide the app id of the Entra AD app that has the required permissions
.PARAMETER $app_secret
    provide the app secret of the Entra AD app that has the required permissions
.PARAMETER $tenantId
    provide the tenant id of the tenant where the app is registered
.PARAMETER $daysSinceLastConnection
    provide the amount of days since the last connection of the cloud pc to revoke the license, default is 30
.PARAMETER $simulationMode
    provide if the script should run in simulation mode or not, default is true
.INPUTS
  none
.OUTPUTS
  Output is writen to console
.NOTES
  Version:        1.0
  Author:         Dieter Kempeneers
  Creation Date:  2024-07-14
  Purpose/Change: Initial script development
  
.EXAMPLE
  Run in sumulation mode with default parameters
  .\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>"
  Run in simulation mode with with another amount of days since last connection 
  .\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -daysSinceLastConnection 60
  Run the script to actually remove the users from the group
  .\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -simulationMode $false
  Run the script to actually remove the users from the group with another amount of days since last connection
  .\Windows365-RevokeUnusedLicense.ps1 -app_id "<app_id>" -app_secret "<app_secret>" -tenantId "<tenantId>" -simulationMode $false -daysSinceLastConnection 60
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
function  revoke-Windows365UnusedLicense(){
    param(
        [string]$app_id,
        [string]$app_secret,
        [string]$tenantId,
        [int]$daysSinceLastConnection = 30,
        [bool]$simulationMode = $true
    )

    #if any of the above required parameters are not provided, exit
    if ($app_id -eq $null -or $app_secret -eq $null -or $tenantId -eq $null){
        Write-Error "Please provide all required parameters"
        exit
    }

    $today = Get-Date

    #-----------------------------------------------------------[Functions]------------------------------------------------------------
    function get-graphToken() {
        # $token = (Get-AzAccessToken -ResourceUrl https://graph.microsoft.com).Token
        # Return "Bearer " + ($token).ToString()
        param(
            [string]$TenantID,
            [string]$ClientID,
            [string]$ClientSecret
        )


        $graphURL = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"

        $Body = @{
        
            'client_id'     = $ClientID
            'grant_type'    = 'client_credentials'
            'client_secret' = $ClientSecret
            'scope'         = 'https://graph.microsoft.com/.default'
        }
        
        $params = @{
            ContentType = 'application/x-www-form-urlencoded'
            Headers     = @{'accept' = 'application/json' }
            Body        = $Body
            Method      = 'Post'
            URI         = $graphURL
        }
        try {
            $token = Invoke-RestMethod @params 
        } catch {
            if ($null -ne $_.Exception){
                Write-Error "$($_.Exception)"
                break
            } 
        }
        
        Return "Bearer " + ($token.access_token).ToString()
    }

    function get-groupMembers(){
        param(
            [string]$graphtoken,
            [string]$groupID
        )
        $graphURL = "https://graph.microsoft.com/beta/groups/$($groupID)/members"

    
        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
            'ConsistencyLevel' = 'eventual'
        }
        
        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5
        while ($RetryCount -le $MaxRetries) {
            do {
                try {
                        $Response = Invoke-WebRequest -Uri $graphURL -Method Get -Headers $authHeader
                        $PageResults = $Response.Content | ConvertFrom-Json
                        if ($null -eq $pageResults) {
                            Write-Error "Error fetching API data"
                            if ($RetryCount -le $MaxRetries) {
                                write-host "Retrying in $RetryAfter seconds..."
                                Start-Sleep -Seconds $RetryAfter
                            }
                        } else {
                            return $pageResults.value
                        }
                } catch {
                        Write-Error "$($_.Exception.Message)"
                        $RetryCount++
                        if ($RetryCount -le $MaxRetries) {
                            write-host "Retrying in $RetryAfter seconds..."
                            Start-Sleep -Seconds $RetryAfter
                            $RetryAfter += $RetryAfter
                        }
                    
                }
            } while ($retryCount -gt 0)
        }

    }

    function remove-groupMember(){
        param(
            [string]$graphtoken,
            [string]$userId,
            [string]$groupId
        )
        # $userId = $unusedCloudPC.userId
        # $groupId = $unusedCloudPC.assignmentGroupId
        $graphURL = "https://graph.microsoft.com/v1.0/groups/$($groupId)/members/$($userId)/`$ref"

    
        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
        }
        
        $successful = $false
        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5
        while ($RetryCount -le $MaxRetries -and -not $successful) {
            try {
                    $Response = Invoke-WebRequest -Uri $graphURL -Method Delete -Headers $authHeader
                    if ($null -ne $response){
                        if ($response.StatusCode -eq "204") {
                            $successful = $true
                        } else {
                            write-error "Error removing user from group"
                        }
                    } 
            } catch {
                    Write-Error "$($_.Exception.Message)"
                    $RetryCount++
                    if ($RetryCount -le $MaxRetries) {
                        write-host "Retrying in $RetryAfter seconds..."
                        Start-Sleep -Seconds $RetryAfter
                        $RetryAfter += $RetryAfter
                    }
                    
            }
            
        }

        return $successful

    }

    function get-allProvisioningPolicies(){
        param(
            [string]$graphtoken
        )
        $graphURL = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/provisioningPolicies?`$expand=assignments"

    
        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
            'X-Ms-Command-Name' = 'fetchPolicyList'
            'ConsistencyLevel' = 'eventual'
        }
        
        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5
        while ($RetryCount -le $MaxRetries) {
            do {
                try {
                        $Response = Invoke-WebRequest -Uri $graphURL -Method Get -Headers $authHeader
                        $PageResults = $Response.Content | ConvertFrom-Json
                        if ($null -eq $pageResults) {
                            Write-Error "Error fetching API data"
                            if ($RetryCount -le $MaxRetries) {
                                write-host "Retrying in $RetryAfter seconds..."
                                Start-Sleep -Seconds $RetryAfter
                            }
                        } else {
                            return $pageResults.value
                        }
                } catch {
                        Write-Error "$($_.Exception.Message)"
                        $RetryCount++
                        if ($RetryCount -le $MaxRetries) {
                            write-host "Retrying in $RetryAfter seconds..."
                            
                            Start-Sleep -Seconds $RetryAfter
                            $RetryAfter += $RetryAfter
                        }
                    
                }
            } while ($retryCount -gt 0)
        }

    }

    function get-allCloudPCs(){
        param(
            [string]$graphtoken
        )
        $graphURL = "https://graph.microsoft.com/v1.0/deviceManagement/virtualEndpoint/cloudPCs?`$expand=*"

    
        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
            'ConsistencyLevel' = 'eventual'
        }
        
        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5
        while ($RetryCount -le $MaxRetries) {
            do {
                try {
                        $Response = Invoke-WebRequest -Uri $graphURL -Method Get -Headers $authHeader
                        $PageResults = $Response.Content | ConvertFrom-Json
                        if ($null -eq $pageResults) {
                            Write-Error "Error fetching API data"
                            if ($RetryCount -le $MaxRetries) {
                                write-host "Retrying in $RetryAfter seconds..."
                                Start-Sleep -Seconds $RetryAfter
                            }
                        } else {
                            return $pageResults.value
                        }
                } catch {
                        Write-Error "$($_.Exception.Message)"
                        $RetryCount++
                        if ($RetryCount -le $MaxRetries) {
                            write-host "Retrying in $RetryAfter seconds..."
                            Start-Sleep -Seconds $RetryAfter
                            $RetryAfter += $RetryAfter
                        }
                    
                }
            } while ($retryCount -gt 0)
        }

    }

    function get-cloudPCConnectionReport(){
        param(
            [string]$graphtoken
        )
        $graphURL = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports/"

        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
            'ConsistencyLevel' = 'eventual'
        }

        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5

        $cloudPCs = @()
        $allRecords = @()

        $top = 50
        $skip = 0

        $Success = $false

        while ($RetryCount -le $MaxRetries -and -not $Success) {
            try {
                do {
                    $Body = @{
                        "top"       = $($top)
                        "skip"      = $($skip)
                        "search"    = ""
                        "filter"    = ""
                        "select"    = @("CloudPcId","ManagedDeviceName","UserPrincipalName","TotalUsageInHour","LastActiveTime","PcType")
                        "orderBy"   = @("TotalUsageInHour")
                    }

                    $Body = $body | ConvertTo-Json -Depth 5
                    $response = Invoke-RestMethod -Uri $graphURL -Method Post -Headers $authHeader -Body $Body 
                    Write-Host "Fetched data for $($response.TotalRowCount) Cloud PCs"

                    if ($null -ne $response -and $response.Values.Count -gt 0) {
                        $allRecords += $response.Values
                        $skip += $top # Move the skip value by the amount of top

                        # Loop through each value set to convert to custom object
                        foreach ($valueSet in $response.Values) {
                            # Create a new hashtable for the custom object
                            $cloudPC = @{}
                            
                            # Loop through each schema and corresponding value
                            for ($i = 0; $i -lt $response.Schema.Count; $i++) {
                                $columnName = $response.Schema[$i].Column
                                $columnValue = $valueSet[$i]
                                
                                # Add property to the custom object
                                $cloudPC[$columnName] = $columnValue
                            }
                            # Add additional fields that we need later on
                            $cloudPC["assignmentGroupId"] = ""
                            $cloudPC["provisioningPolicyId"] = ""
                            $cloudPC["serviceplanId"] = ""
                            $cloudPC["lastModifiedDateTime"] = ""
                            $cloudPC["userId"] = ""

                            # Convert hashtable to PSObject and add to the array
                            $cloudPCs += [PSCustomObject]$cloudPC
                        }
                    } else {
                        Write-Error "Error fetching API data"
                        if ($RetryCount -le $MaxRetries) {
                            write-host "Retrying in $RetryAfter seconds..."
                            Start-Sleep -Seconds $RetryAfter
                            $RetryCount++
                        }
                    }
                } while ($response.Values.Count -eq $top -and $RetryCount -le $MaxRetries)

                if ($cloudPCs.Count -gt 0) {
                    $Success = $true
                }
            } catch {
                Write-Error "$($_.Exception.Message)"
                $RetryCount++
                if ($RetryCount -le $MaxRetries) {
                    write-host "Retrying in $RetryAfter seconds..."
                    Start-Sleep -Seconds $RetryAfter
                    $RetryAfter += $RetryAfter
                }
            }
        }

        # Return object
        return $cloudPCs
    }

    function get-allProvisionedCloudPCsPerAssignment(){
        param(
            [string]$graphtoken,
            [string]$entraGroupID,
            [string]$servicePlanId
        )
        $graphURL = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/cloudPCs/getProvisionedCloudPCs(groupId='$($entraGroupID)',servicePlanId='$($servicePlanId)')?`$expand=*"

    
        $authHeader = @{
            'Authorization' = "$graphToken"
            'Content-Type'  = 'application/json'
            'ConsistencyLevel' = 'eventual'
        }
        
        $RetryCount = 0
        $MaxRetries = 4
        $RetryAfter = 5
        while ($RetryCount -le $MaxRetries) {
            do {
                try {
                        $Response = Invoke-WebRequest -Uri $graphURL -Method Get -Headers $authHeader
                        $PageResults = $Response.Content | ConvertFrom-Json
                        if ($null -eq $pageResults) {
                            Write-Error "Error fetching API data"
                            if ($RetryCount -le $MaxRetries) {
                                write-host "Retrying in $RetryAfter seconds..."
                                Start-Sleep -Seconds $RetryAfter
                            }
                        } else {
                            return $pageResults.value
                        }
                } catch {
                        Write-Error "$($_.Exception.Message)"
                        $RetryCount++
                        if ($RetryCount -le $MaxRetries) {
                            write-host "Retrying in $RetryAfter seconds..."
                            Start-Sleep -Seconds $RetryAfter
                            $RetryAfter += $RetryAfter
                        }
                    
                }
            } while ($retryCount -gt 0)
        }

    }

    function test-cloudPCprovisionedByAssignmentID(){
        param(
            [string]$graphtoken,
            [string]$cloudPCid,
            [string]$servicePlanId,
            [string]$assignmentID
        )

        $cloudPCsPerAssignment = get-allProvisionedCloudPCsPerAssignment -graphtoken $graphtoken -entraGroupID $assignmentID -servicePlanId $servicePlanId

        #if Cloud PC part of above array it's provisioned by this provisioning policy
        $foundCloudPC = $cloudPCsPerAssignment | ? {$_.id -eq $cloudPC.id}

        if ($foundCloudPC){
            return $true
        } else {
            return $false
        
        }

    }

    #-----------------------------------------------------------[Execution]------------------------------------------------------------
    #authenticate
    $graphtoken = get-graphToken -TenantID $tenantId -ClientID $app_id -ClientSecret $app_secret

    if ($graphtoken){
        
        #get CloudPC usage report
        $cloudPCUsage = get-cloudPCConnectionReport -graphtoken $graphtoken

        #filter cloud pcs where last active time is longer ago than days since last connection, count from today.
        $unusedCloudPCs = $cloudPCUsage | Where-Object {$_.LastActiveTime -lt ($today.AddDays(-$daysSinceLastConnection))}

        $allProvisioningPolicies = get-allProvisioningPolicies -graphtoken $graphtoken
        $allCloudPCs = get-allCloudPCs -graphtoken $graphtoken

        #if there are no unused cloud PCs, exit
        if ($unusedCloudPCs.Count -gt 0) {
            #Get assignment group of unused cloud PCs

            #add the provisioning policy id to the unusedcloudpc object
            $unusedCloudPC = $unusedCloudPCs[0]
            foreach ($unusedCloudPC in $unusedCloudPCs) {
                $cloudPC = $allCloudPCs | ? {$_.id -eq $unusedCloudPC.CloudPcId}
                $unusedCloudPC.provisioningPolicyId = $cloudPC.provisioningPolicyId
                $unusedCloudPC.serviceplanId = $cloudPC.servicePlanId
                $unusedCloudPC.lastModifiedDateTime = $cloudPC.lastModifiedDateTime

                #if lastactive is null make sure that lasmtmodified day is also further away than days since last connection and set the value as lastactive to continue working with it
                if ($null -eq $unusedCloudPC.LastActiveTime){
                        $unusedCloudPC.LastActiveTime = $unusedCloudPC.lastModifiedDateTime
                }

                #last check to verify is last active day is more than days since last connection, because we had to fill in the value last minute for the null values
                #this prevents new cloud pcs from being removed
                if ($unusedCloudPC.LastActiveTime -lt ($today.AddDays(-$daysSinceLastConnection))){
                    
                    #get all assignments of the provisioning policy
                    $possibleAssignments = @(($allProvisioningPolicies | ? {$_.id -eq $unusedCloudPC.provisioningPolicyId}).assignments)

                    #Check if the user is in the active assignments and check if the correct license is assigned, if yes remove.
                    $assignment = $possibleAssignments[0]
                    foreach ($assignment in $possibleAssignments) {
                        
                    #if user is provisioned the cloudpc through this assignment, remove user from the group assignment
                    $correctAssignment = test-cloudPCprovisionedByAssignmentID -graphtoken $graphtoken -cloudPCid $unusedCloudPC.id -servicePlanId $cloudPC.servicePlanId -assignmentID $assignment.id     
            
                        if ($correctAssignment){
                            #add assignment group id to cloudpc object
                            $unusedCloudPC.assignmentGroupId = $assignment.id
                            $groupmembers = @(get-groupmembers -graphtoken $graphtoken -groupId $assignment.id)
        
                            $foundUser = $groupmembers | ? {$_.userPrincipalName -eq $cloudPC.UserPrincipalName}
                            #add user id to cloudpc object
                            $unusedCloudPC.userId = $foundUser.id

                            if ($null -ne $foundUser) {
                                #remove user from group
                                if ($simulationMode -eq $true){
                                    Write-Output "SIMULATEION MODE: Would remove license for $($unusedCloudPC.UserPrincipalName), user is member from Entra ID group: $($assignment.id)"
                                } else {
                                    Write-Output "Removing license for $($unusedCloudPC.UserPrincipalName), removing user from Entra ID group: $($assignment.id)"
                                }
                                if ($simulationMode -eq $false){
                                    #remove user from group
                                    $response = remove-groupMember -graphtoken $graphtoken -userId $unusedCloudPC.userId -groupId $unusedCloudPC.assignmentGroupId
                                    if ($response){
                                        Write-Output "User $($unusedCloudPC.UserPrincipalName) succesfully removed from group with ID $($assignment.id)"
                                    } 
                                }

                            } else {
                                Write-Output "User $($unusedCloudPC.UserPrincipalName) should be in Group with ID $($assignment.id) but could not be found."
                            }
                        } else {
                            Write-Output "Cloud PC for $($unusedCloudPC.UserPrincipalName) is not part of assignment in group id: $($assignment.id) or cloud pc is not in provisioned state"
                        }
                    }

                } else {
                    Write-Output "Cloud PC for $($unusedCloudPC.UserPrincipalName) is only recently provisioned, skipping"
                }
            }

        } else {
            Write-Output "No unused Cloud PCs found"
            exit
        }
    }
}