<#
.SYNOPSIS
    This script sends a Lost Mode command to any iOS device that is currently marked as Non-Compliant within Endpoint Manager and
    does not fall under the grace period category. 

.DESCRIPTION
    This script uses Graph API to send a Lost Mode command to Non-compliant devices based on a Compliance Policy ID. MS Graph 
    authentication is handled using an Azure Application which has RBAC access to the Azure API.  

.HELP
    To retrieve Complaince Policy ID 
     Get-DeviceManagement_DeviceCompliancePolicies -Select displayName, id


.NOTES
    Version:          1.4
    Author:           Stephen Devlin
    Creation Date:    22.10.21
    Purpose/Change:   Addition of passkey removal.
                     
#>
# AZURE GRAPH API AUTHENTICATION

#-------------------------------------------------------#
# INSTALL MS GRAPH POWERSHELL MODULE
If(-not(Get-InstalledModule Microsoft.Graph -ErrorAction silentlycontinue)){
    Install-Module Microsoft.Graph -Confirm:$False -Force
}

#-------------------------------------------------------#
# RETRIEVE NON COMPLIANCE DEVICES FROM GRAPH API VIA COMPLAINCE ID
$tenant = “Your Tenant ID”
$authority = “https://login.microsoftonline.com/$tenant”
$clientId = “Your Application ID”
$clientSecret = "Your Application Secret"
Update-MSGraphEnvironment -AppId $clientId -Quiet
Update-MSGraphEnvironment -AuthUrl $authority -Quiet
Connect-MSGraph -ClientSecret $ClientSecret -Quiet
Update-MSGraphEnvironment -SchemaVersion 'beta'
Connect-MSGraph -ClientSecret $ClientSecret -Quiet

$ComplaincePolicyID = "Your Complaince Policy ID"
$Devices = Get-DeviceManagement_DeviceCompliancePolicies_DeviceStatuses -deviceCompliancePolicyId $ComplaincePolicyID

# FILTER NONCOMLIANT DEVICES TO REMOVE THOSE IN GRACE PERIOD
$nonCompliant = $Devices | Where-Object {($_.status -eq "noncompliant" -and ($_.complianceGracePeriodExpirationDateTime -lt $currentDate))}

# OUTPUT NON COMPLIANT DEVICES TO CSV
$nonCompliant | Select-Object userName, deviceDisplayName, complianceGracePeriodExpirationDateTime, lastReportedDateTime | Export-Csv "C:\Logs\Compliance\iPad\$((Get-Date).ToString("dd-MM-yyyy"))_iPad-LostMode.csv" -NoTypeInformation

#-------------------------------------------------------#
# FILE UPLOAD TO SHAREPOINT - WITH APPLICATION AUTH
$SiteURL = "Your SharePoint URL"
$pnpClientID = "Your PNP Client ID"
$pnpSecret = "Your PNP Client ID"

Connect-PnPOnline -Url $SiteURL -ClientId $pnpClientID -ClientSecret $pnpSecret
$FilesLocal = "C:\Logs\Compliance\iPad"
$Library = "Your SharePoint Library Directory"
$Files = Get-ChildItem -Path $FilesLocal -Force -Recurse
ForEach ($File in $Files)
{Add-PnPFile -Path "$($File.Directory)\$($File.Name)" -Folder $Library }

# FILE CLEAN UP 
Remove-Item -Path "C:\Logs\Compliance\iPad\$((Get-Date).ToString("dd-MM-yyyy"))_iPad-LostMode.csv"

#-------------------------------------------------------#
# LOCK NONCOMPLIANT USERS VIA GRAPH API
foreach ($device in $nonCompliant)
{   
    #Get MEM device ID
    $id = ($device.id).ToString().split("_")
    $UID = $id.GetValue(2)
    $URL="https://graph.microsoft.com/beta/deviceManagement/managedDevices/$UID/enableLostMode"
            $BodyJson = @"
            {
                "message": "The security system has identified that your Device no longer meets our security requirements. Please contact the IT to unlock your device."
                "footer": "COMPANY NAME"
            }
"@
    #SEND LOST MODE FUNCTION TO DEVICE VIA GRAPH API
    Invoke-MSGraphRequest -HttpMethod POST -Url $URL -Content $BodyJson
}
#-------------------------------------------------------#
#REMOVE USER ASSIGNED PASSCODE TO ENSURE KEYCHAIN DOES NOT LOCKOUT
foreach ($device in $nonCompliant)
{
    $RemovePasscode = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$UID/resetPasscode"
    Invoke-MSGraphRequest -HttpMethod POST -Url $RemovePasscode
}