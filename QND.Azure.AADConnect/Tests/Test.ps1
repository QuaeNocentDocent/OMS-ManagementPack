Function Format-Time
{
	[OutputType([String])]
	param($utcTime)


	$fTime=$utcTime.ToString('yyyy-MM-dd hh:mm:ss tt')
	#don't know why tt doens't work
	#quick fix without reverting to -net framework formatting
	if($fTime.IndexOf('M') -eq -1) {
		if ($utcTime.Hour -lt 13) {$fTime+= 'AM'} else {$fTime += 'PM'}
	}
	return $fTime
}

#region trigger disocvery
$EventLog='Operations Manager'
$EventSource='QND Script'
$EventId=1
$msg='QND Manual'
$key='/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/MaaS/providers/Microsoft.Automation/automationAccounts/prgGenericMaaS' ##$parameters=@('RecoveryContainer')



if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
    [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $EventLog)
}

$nativeType=[System.Diagnostics.EventLogEntryType]::Information

$event = New-Object System.Diagnostics.EventInstance($eventID,1,$nativeType)

$evtObject = New-Object System.Diagnostics.EventLog;
$evtObject.Log = $EventLog;
$evtObject.Source = $EventSource;
$parameters = @($msg) + $key
$evtObject.WriteEvent($event, $parameters)
#endregion  

Import-module C:\Local\dev\OpsMgr\GIT\QND.OMS\AzureMPIntegration\QNDAdal
import-module C:\Local\dev\OpsMgr\GIT\QND.OMS\AzureMPIntegration\QNDAzure
[System.Reflection.Assembly]::LoadFrom("C:\Users\grandinid\SkyDrive\Dev\POSHRepo\Modules\QNDAdal\Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll")




#Lab logon on
$authBaseAddress='https://login.windows.net/prelabs.onmicrosoft.com/'
$resourcebaseAddress='https://management.azure.com/'
$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress

#region ecloud logon
  $authBaseAddress='https://login.windows.net/progelazureclioutlook.onmicrosoft.com/'
 $resourcebaseAddress='https://management.azure.com/'
$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress
#endregion

#region service account logon
 $authBaseAddress='https://login.windows.net/manutencoop.onmicrosoft.com/'
$ADUserName='3883d139-6084-4ea6-a67b-4a53e56af64c'
$ClientId=$ADUserName
$ADPassword='f9YLvIwBqzoaFL2erf1U3wP76v91ONE4NAnqcOSYIl8='
$pwd = ConvertTo-SecureString $ADPassword -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential ($ADUserName, $pwd)
	$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $cred
#endregion


$connection=$authority.CreateAuthorizationHeader()
$nextLink=$null
$timeout=300
$guid= '{{{0}}}' -f (new-guid).toString()

<#get access token from context
  #doesn't work because we're currently suing a different authority
  Login-AzureRmAccount
  $context=Get-AzureRmContext
  $token=$context.TokenCache.ReadItems() | where {$_.TenantId -ieq $context.Tenant -and $_.DisplayableId -ieq $context.Account -and $_.Resource -ieq 'https://management.core.windows.net/'} | select -First 1
  $accessToken = 'Bearer {0}' -f $token.AccessToken
#>

<#
Log types
  AADCHealth_Service_CL (ServiceType, ServiceId)
  AADCHealth_Server_CL (ServiceType, ServiceId, ServerId) #better than Computer cause if we're per node it get's counted
  AADCHealth_Alert_CL (ServiceType, ServiceId, ServerId, ALertGuid)

  # alert when we have an alert whose last status reported for the id is Active, how can we do this in Kusto?
KempStatus_CL
| summarize arg_max(TimeGenerated,*) by index_s

  $tenantId='cdbd1c91-a932-4c62-ae77-e13bfe7f4166'
  $credential=(get-credential -UserName svc_automation@prelabs.onmicrosoft.com -message '.')
#>


if(! (get-module -Name QNDAdal)) {Import-Module QNDAdal}

$baseep='https://api.aadconnecthealth.azure.com/v1/connectHealth'
$baseresource="https://management.core.windows.net/"

#import-module qndadal
$authority='https://login.windows.net/common/oauth2/authorize'
$connection = get-adalauthentication -authority $authority -resourceURI $baseresource -credential $credential
$tenantId=$connection.TenantId

$header = @{
  "Content-Type"="application/json"
  "Accept"="application/json"
  "Authorization"= $connection.CreateAuthorizationHeader()
}

$uri = '{0}/{1}' -f $baseep, $tenantId
$uri = '{0}/{1}/syncServices' -f $baseep, $tenantId
$uri = '{0}/{1}/adfsServices' -f $baseep, $tenantId
$uri = '{0}/{1}/addsServices' -f $baseep, $tenantId

$uri = '{0}/{1}/syncServices/de2565bf-eae5-434c-aadf-9a28902bb406/servers' -f $baseep, $tenantId
$uri = '{0}/{1}/adfsServices/f06cb320-1967-4671-b93d-2f9ec3bf9483/servers' -f $baseep, $tenantId
$uri = '{0}/{1}/addsServices/a29ed5f6-e6a4-4e2d-a317-70a870df9fe5/servers' -f $baseep, $tenantId

$filter='?$filter=createdDateTime gt {0}Z' -f $startFrom.ToUniversalTime().ToString('s')
$uri = '{0}/{1}/syncServices/de2565bf-eae5-434c-aadf-9a28902bb406/alerts{2}' -f $baseep, $tenantId, $filter
$uri = '{0}/{1}/adfsServices/f06cb320-1967-4671-b93d-2f9ec3bf9483/alerts' -f $baseep, $tenantId

$uri = '{0}/{1}/addsServices/a29ed5f6-e6a4-4e2d-a317-70a870df9fe5/alerts' -f $baseep, $tenantId

$nextLink=$null
$body=$null
$token=$connection.CreateAuthorizationHeader()
try {
$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($token) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose -ErrorAction SilentlyContinue
}
catch {
    write-host 'got you'
}

try {
  $result = invoke-webrequest -Method GET -uri $uri -Headers $header -UseBasicParsing
  $parsed = $result.Content | ConvertFrom-Json
  $parsed
}
catch {
  write-host $_
}

$guid= '{{{0}}}' -f (new-guid).toString()

$cred=Get-CRedential

C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.Azure.AADConnect\Scripts\Get-AADConnectHealth.ps1 -traceLevel 5 -SourceID $guid -ManagedEntityId $guid -clientId 1950a258-227b-4e31-a9cf-717495945fc2 -SubscriptionId 17c8f3bf-56fd-40dd-8860-28f3e426043a -Proxy $null `
   -AuthBaseAddress 'https://login.windows.net/common/'  -ResourceBaseAddress 'https://management.core.windows.net/' `
   -ADUserName $cred.UserName -ADPassword $cred.GetNetworkCredential().Password `
   -resourceURI https://api.aadconnecthealth.azure.com/v1/connectHealth `
   -verbose

C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.Azure.AADConnect\Scripts\Get-AADConnectHealth.ps1 -traceLevel 5 -SourceID $guid -ManagedEntityId $guid -clientId 1950a258-227b-4e31-a9cf-717495945fc2 -SubscriptionId 17c8f3bf-56fd-40dd-8860-28f3e426043a -Proxy $null `
   -AuthBaseAddress 'https://login.windows.net/common/'  -ResourceBaseAddress 'https://management.core.windows.net/' `
   -ADUserName 'svc_azuremonitoring@progel.onmicrosoft.com' -ADPassword 'stack-NxJbhzUp' `
   -resourceURI https://api.aadconnecthealth.azure.com/v1/connectHealth `
   -verbose
C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.Azure.AADConnect\Scripts\Get-AADConnectHealth.ps1 -traceLevel 5 -sourceID '{9D44D2A9-B2EF-1C77-1E13-FAF251765DC1}' -ManagedEntityId '{FE60B6DD-5228-35BA-58CA-06BD7C9E23F6}' 
  -clientId '1950a258-227b-4e31-a9cf-717495945fc2' -SubscriptionId '17c8f3bf-56fd-40dd-8860-28f3e426043a' 
   -AuthBaseAddress 'https://login.windows.net/common/' -ResourceBaseAddress 'https://management.core.windows.net' -ADUserName 'svc_azuremonitoring@progel.onmicrosoft.com' -ADPassword 'stack-NxJbhzUp' -resourceURI 'https://api.aadconnecthealth.azu
re.com/v1/connectHealth' -verbose

C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.Azure.AADConnect\Scripts\Get-AADConnectHealth.ps1 -traceLevel 5 -sourceID {9D44D2A9-B2EF-1C77-1E13-FAF251765DC1} -ManagedEntityId {FE60B6DD-5228-35BA-58CA-06BD7C9E23F6} -clientId 1950a258-227b-4e31-a9cf-717495945fc2 -SubscriptionId 17c8f3bf-56fd-40dd-8860-28f3e426043a -Proxy $null -AuthBaseAddress https://login.windows.net/common/oauth2/authorize -ResourceBaseAddress https://management.core.windows.net/ -ADUserName svc_azuremonitoring@progel.onmicrosoft.com -ADPassword stack-NxJbhzUp -resourceURI https://api.aadconnecthealth.azure.com/v1/connectHealth -verbose
   'e423aad8-8360-487e-8173-cecdc3c408c9'
   'ae8996b3-84ee-4e14-9c7a-35bb8de53d80'

<#
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/syncServices","value":[
    {
      "id":"de2565bf-eae5-434c-aadf-9a28902bb406","displayName":"prelabs.onmicrosoft.com","healthStatus":"Error","activeAlertsCount":3,"resolvedAlertsCount":7,"lastDataUploadDateTime":"2017-11-01T15:15:55.3215397Z","emailNotificationEnabled":true,"emailAllGlobalAdminsEnabled":true,"emailNotificationAddresses":[

      ]
    }
  ]
}
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/syncServices('de2565bf-eae5-434c-aadf-9a28902bb406')/servers","value":[
    {
      "id":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"PRE-ADSYNC","healthStatus":"Error","activeAlertsCount":3,"resolvedAlertsCount":7,"lastDataUploadDateTime":"0001-01-01T00:00:00Z"
    }
  ]
}
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/syncServices('de2565bf-eae5-434c-aadf-9a28902bb406')/alerts","value":[
    {
      "id":"ded98f15-f4a3-483a-ad1b-27fbb19dd52a","alertLevel":"Error","alertState":"Active","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Export to Active Directory failed.","description":"<p>The export operation to Active Directory Connector has failed.</p>","remediation":"\n      <p>\n        <b>Please investigate the event log errors of export operation for further details.</b>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"Export"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-24T05:36:45.65Z","resolvedDateTime":"0001-01-01T00:00:00Z","lastDetectedDateTime":"2017-11-01T15:11:42.033Z"
    },{
      "id":"b0133ce0-1a97-4304-8484-cd124b61369d","alertLevel":"Error","alertState":"Active","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Import from Active Directory failed.","description":"<p>Import from Active Directory failed. As a result, objects from some domains from this forest may not be imported.</p>","remediation":"\n      <p>\n        <ol>\n          <li>Verify DC connectivity</li>\n          <li>Re-run import manually</li>\n          <li>Investigate event log errors of the import operation for further details</li>\n        </ol>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"DeltaImport"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-24T05:36:17.487Z","resolvedDateTime":"0001-01-01T00:00:00Z","lastDetectedDateTime":"2017-11-01T15:41:16.59Z"
    },{
      "id":"d12d27b2-87e0-4af2-b62e-0f70e247c810","alertLevel":"Error","alertState":"Active","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Password Synchronization heartbeat was skipped in last 120 minutes.","description":"<p>Password Synchronization has not connected with Azure Active Directory in the last 120 minutes. As a result passwords will not be synchronized with Azure Active Directory.</p>","remediation":"\n      <p>\n        <b>Restart Microsoft Azure Active Directory Sync Services:</b><br>\n
       Please note that any synchronization operations that are currently running will be interrupted. \n        You can chose to perform below steps when no synchronization operation is in progress.<br>\n        1. Click <b>Start</b>, click <b>Run</b>, type <b>Services.msc</b>, and then click <b>OK</b>.<br>\n        2. Locate <b>Microsoft Azure AD Sync</b>, right-click it, and then click <b>Restart</b>.\n
     </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[

      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-28T09:38:16.4751552Z","resolvedDateTime":"0001-01-01T00:00:00Z","lastDetectedDateTime":"2017-11-01T14:33:53.1485094Z"
    },{
      "id":"1834034b-381f-49bc-a88d-ec0728fd406f","alertLevel":"Error","alertState":"ResolvedByPositiveResult","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Azure AD Connect Sync Service is not running","description":"<p>Microsoft Azure AD Sync Windows service is not running or could not start. As a result, objects will not synchronize with Azure Active Directory.</p>","remediation":"\n      <p>\n        <b>Start Microsoft Azure Active Directory Sync Services</b>\n        <ol>\n          <li>Click <b>Start</b>, click <b>Run</b>, type <b>Services.msc</b>, and then click <b>OK</b>.</li>\n          <li>Locate the <b>Microsoft Azure AD Sync service</b>, and then check whether the service is started. If the service isn't started, right-click it, and then click <b>Start</b>.</li>\n        </ol>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Service Status","value":"ServiceNotRunning"
        }
      ],"resolvedAlertDetails":[
        {
          "key":"Service Status","value":"Success"
        }
      ],"createdDateTime":"2017-08-15T02:48:16.6367737Z","resolvedDateTime":"2017-08-15T03:35:13.1936858Z","lastDetectedDateTime":"2017-08-15T03:18:17.0523919Z"
    },{
      "id":"a0d6f24c-d867-4159-865e-4d3e5f53af7f","alertLevel":"Warning","alertState":"ResolvedByStateChange","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Export to Active Directory failed.","description":"<p>The export operation to Active Directory Connector has failed.</p>","remediation":"\n      <p>\n        <b>Please investigate the event log errors of export operation for further details.</b>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"Export"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-12T04:11:26.333Z","resolvedDateTime":"2017-10-12T04:41:32.397Z","lastDetectedDateTime":"2017-10-12T04:11:26.333Z"
    },{
      "id":"5ad8a1d7-58b6-4b22-8658-ec402ee2555e","alertLevel":"Warning","alertState":"ResolvedByStateChange","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Import from Active Directory failed.","description":"<p>Import from Active Directory failed. As a result, objects from some domains from this forest may not be imported.</p>","remediation":"\n      <p>\n        <ol>\n          <li>Verify DC connectivity</li>\n          <li>Re-run import manually</li>\n          <li>Investigate event log errors of the import operation for further details</li>\n        </ol>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"DeltaImport"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-12T04:09:39.17Z","resolvedDateTime":"2017-10-12T04:39:40.023Z","lastDetectedDateTime":"2017-10-12T04:09:39.17Z"
    },{
      "id":"9714d957-8675-4d18-85d0-459a41373cc3","alertLevel":"Error","alertState":"ResolvedByTimer","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Export to Active Directory failed.","description":"<p>The export operation to Active Directory Connector has failed.</p>","remediation":"\n      <p>\n
   <b>Please investigate the event log errors of export operation for further details.</b>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"Export"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-12T04:41:32.397Z","resolvedDateTime":"2017-10-22T02:30:49.7072897Z","lastDetectedDateTime":"2017-10-19T01:23:24.52Z"
    },{
      "id":"70badb01-6b44-4ed2-b337-b1863610b3d9","alertLevel":"Error","alertState":"ResolvedByTimer","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Import from Active Directory failed.","description":"<p>Import from Active Directory failed. As a result, objects from some domains from this forest may not be imported.</p>","remediation":"\n      <p>\n        <ol>\n          <li>Verify DC connectivity</li>\n          <li>Re-run import manually</li>\n          <li>Investigate event log errors of the import
operation for further details</li>\n        </ol>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"DeltaImport"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-12T04:39:40.023Z","resolvedDateTime":"2017-10-22T02:31:01.3577269Z","lastDetectedDateTime":"2017-10-19T01:22:50.507Z"
    },{
      "id":"2046428b-eb88-4de0-9eac-c8a8cd556e3b","alertLevel":"Warning","alertState":"ResolvedByStateChange","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Export to Active Directory failed.","description":"<p>The export operation to Active Directory Connector has failed.</p>","remediation":"\n      <p>\n        <b>Please investigate the event log errors of export operation for further details.</b>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"Export"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-24T04:06:38.58Z","resolvedDateTime":"2017-10-24T05:36:45.65Z","lastDetectedDateTime":"2017-10-24T04:06:38.58Z"
    },{
      "id":"1fb2d5b0-0c5d-470a-905b-36ce36a1f8c8","alertLevel":"Warning","alertState":"ResolvedByStateChange","alertScopeDisplayName":"PRE-ADSYNC","serviceId":"de2565bf-eae5-434c-aadf-9a28902bb406","serverId":"9c16b215-969a-4e29-a68a-517e8393292b","displayName":"Import from Active Directory failed.","description":"<p>Import from Active Directory failed. As a result, objects from some domains from this forest may not be imported.</p>","remediation":"\n      <p>\n        <ol>\n          <li>Verify DC connectivity</li>\n          <li>Re-run import manually</li>\n          <li>Investigate event log errors of the import operation for further details</li>\n        </ol>\n      </p>\n    ","relatedLinks":[

      ],"activeAlertDetails":[
        {
          "key":"Operation Type","value":"DeltaImport"
        },{
          "key":"Connector ID","value":"{93CBDBAA-3D5A-46F4-8A6D-B63E9638B4F2}"
        },{
          "key":"Directory Partition","value":"DC=pre,DC=lab"
        },{
          "key":"Run Step Result","value":"no-start-connection"
        }
      ],"resolvedAlertDetails":[

      ],"createdDateTime":"2017-10-24T04:06:01.603Z","resolvedDateTime":"2017-10-24T05:36:17.487Z","lastDetectedDateTime":"2017-10-24T04:06:01.603Z"
    }
  ]
}
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/adfsServices","value":[
    {
      "id":"f06cb320-1967-4671-b93d-2f9ec3bf9483","displayName":"fs.prelabs.progel.com","healthStatus":"Error","activeAlertsCount":4,"resolvedAlertsCount":327,"lastDataUploadDateTime":"2017-11-01T15:24:59.6490156Z","emailNotificationEnabled":true,"emailAllGlobalAdminsEnabled":true,"emailNotificationAddresses":[

      ]
    }
  ]
}
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/adfsServices('f06cb320-1967-4671-b93d-2f9ec3bf9483')/servers","value":[
    {
      "id":"196b5b62-1782-4c63-8049-197e233834f5","displayName":"PRE-WEBAPP1","healthStatus":"Error","activeAlertsCount":2,"resolvedAlertsCount":69,"lastDataUploadDateTime":"0001-01-01T00:00:00Z"
    },{
      "id":"282cd9ba-5f34-4900-8949-f2683003a91f","displayName":"PRE-ADSYNC","healthStatus":"Error","activeAlertsCount":2,"resolvedAlertsCount":256,"lastDataUploadDateTime":"0001-01-01T00:00:00Z"
    }
  ]
}

{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/addsServices","value":[
    {
      "id":"a29ed5f6-e6a4-4e2d-a317-70a870df9fe5","displayName":"pre.lab","healthStatus":"Healthy","activeAlertsCount":0,"resolvedAlertsCount":0,"lastDataUploadDateTime":"0001-01-01T00:00:00Z","emailNotificationEnabled":true,"emailAllGlobalAdminsEnabled":true,"emailNotificationAddresses":[

      ]
    }
  ]
}
{
  "@odata.context":"https://s1.adhybridhealth.azure.com/v1/$metadata#connectHealth('cdbd1c91-a932-4c62-ae77-e13bfe7f4166')/addsServices('a29ed5f6-e6a4-4e2d-a317-70a870df9fe5')/servers","value":[
    {
      "id":"492ee5bd-c072-42a9-b0d2-f45a206edb8e","displayName":"dclab02.pre.lab","healthStatus":"Healthy","activeAlertsCount":0,"resolvedAlertsCount":0,"lastDataUploadDateTime":"0001-01-01T00:00:00Z"
    }
  ]
}
#>



#region REST Automation  testing
$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE'
$command='/runbooks?api-version=2015-10-31'

$command='/runbooks/ASR-HybridAutomation/?api-version=2015-10-31'
$runbooks = invoke-QNDAzureRestRequest -uri ($uri+$command) -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

$uri='https://management.azure.com//subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/MaaS/providers/Microsoft.Automation/automationAccounts/prgGenericMaaS/jobs?api-version=2015-10-31&$filter=properties/startTime ge 2016-10-03T08:51:18%2B00:00 and properties/endTime le 2016-10-18T08:51:18%2B00:00 and properties/runbook/name eq ''Notify-NewOMSAgent'''

$uri='https://management.azure.com//subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/MaaS/providers/Microsoft.Automation/automationAccounts/prgGenericMaaS/jobs?api-version=2015-10-31&$filter=properties/creationTime ge 2016-10-03T08:51:18%2B00:00 and properties/runbook/name eq ''Notify-NewOMSAgent'''

$uri='https://management.azure.com//subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/MaaS/providers/Microsoft.Automation/automationAccounts/prgGenericMaaS/jobs?api-version=2015-10-31&$filter=properties/creationTime ge 2015-10-03T08:51:18%2B00:00 and properties/runbook/name eq ''Run-OSMReports'''
$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 30 -Verbose
#endregion

#region REST file services
$uri = "https://management.azure.com/subscriptions/fd9e0192-37d2-4e28-9c42-6ae6a768813a/resourceGroups/edsb2c-staging-weu-1/providers/Microsoft.Storage/storageAccounts/mcecsb2cstgstd1/listKeys?api-version=2016-01-01"
$sa='mcecsb2cstgstd1'
$keys = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

    $uriListContainers = 'https://{0}.file.core.windows.net/?comp=list' -f $sa
    $result = Invoke-QNDAzureStorageRequest -uri $uriListContainers -verb GET -key $keys.Values.Keys[0].Value -version '2015-02-21' -searchTag 'Share' -verbose   
    
    if($result.ParsedValues) {
        foreach($share in $result.ParsedValues) {
            write-host ('{0} quota {1}GB' -f $share.name, $share.properties.Quota)
            $uri='https://{0}.file.core.windows.net/{1}?restype=share&comp=stats' -f $sa, $share.Name
            $stats = Invoke-QNDAzureStorageRequest -uri $uri -verb GET -key $keys.Values.Keys[0].Value -version '2015-02-21' -searchTag 'ShareUsage' -rootTag 'ShareStats' -verbose   
            write-host ('Current Usage {0} GB' -f $stats.ParsedValues[0].'#text')
        }
    }

$uri='https://mcecsb2cstgstd1.file.core.windows.net/?comp=list'
$body=$null
$nextLink=$null
$h=@{
    'x-ms-date'=''
    Authorization="[SharedKey|SharedKeyLite] <AccountName>:<Signature>"

}
$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose
#endregion

   $query='Type:Alert SourceSystem=OMS | measure count() As Count, max(TimeGenerated) As Last by AlertName'
   $query='Type:Alert SourceSystem=OMS | dedup AlertName'
   $query='Type:Heartbeat | dedup Computer'
   $startDate=(Get-Date).AddDays(-24)
   $endDate=Get-Date

    $QueryArray = @{query=$Query}

        $QueryArray+= @{start=('{0}Z' -f $startDate.GetDateTimeFormats('s'))}
        $QueryArray+= @{end=('{0}Z' -f $endDate.GetDateTimeFormats('s'))}

    $body = ConvertTo-Json -InputObject $QueryArray

$body=@"
{
    "top": 100,
    "query":  "Type:Heartbeat | dedup Computer",
    "start":  "2016-09-05T17:06:44Z",
    "end":  "2016-09-12T17:06:44Z"
}
"@

    $OMSAPIVersion='2015-11-01-preview'
    $resourceBaseAddress='https://management.azure.com/'
    $resourceUri='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OI-Default-East-US/providers/Microsoft.OperationalInsights/workspaces/bbacc090-abbd-4313-9545-6dd72b96a1f6'

    $resourceUri='/subscriptions/fd9e0192-37d2-4e28-9c42-6ae6a768813a/resourceGroups/OpsManagement-WEU-RG01/providers/Microsoft.OperationalInsights/workspaces/MFMEDSB2C-LA'
    $uri = '{0}{1}/search?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion


$uri='{0}subscriptions/fd9e0192-37d2-4e28-9c42-6ae6a768813a/resourceGroups/OpsManagement-WEU-RG01/providers/Microsoft.OperationalInsights/workspaces/MFMEDSB2C-LA/search/e080eda6-0b6c-4725-a50f-58cb6ab6f867?api-version={1}' -f $ResourceBaseAddress,$OMSAPIVersion


		$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose


$alert = $result.Values[0]
$query=$alert.Query
$startDate=[datetime]$alert.QueryExecutionStartTime
$endDate=[datetime]$alert.QueryExecutionEndTime

#ritorniamo $result.values[0].AlertName su cui facciamo anche suppression, mettiamo un timer reset dopo 1
#oppure leggiamo tutti gli alert e la loro frequenza per quelli non ritornati dalla query se Last (GMT) è più vecchio della frequenza ritorniamo un valore 0, altrimenti il valore di count, il monitor è un nomrale property bag su count


$savedSearches= 'savedSearches?'
    $uri = '{0}{1}/savedSearches?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout #-Verbose
foreach($search in $result.Values) {
    $uri = '{0}{1}/schedules?api-version={2}' -f $ResourceBaseAddress,$search.Id,$OMSAPIVersion
    $schedule = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -ErrorAction SilentlyContinue
    if($schedule.values) {
        #take into account just the first schedule for the search maybe this needs to be changed in future
        if ($schedule.Values[0].properties.Enabled -ieq 'True') {
           $uri = '{0}{1}/actions?api-version={2}' -f $ResourceBaseAddress,$schedule.values.id,$OMSAPIVersion
           $actions = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout #-ErrorAction SilentlyContinue
           if ($actions.Values) {
                if ($actions.Values[0].properties.Type -ieq 'Alert') {
                    Write-Host ('{0}, Interval={1}, Name={2}' -f $schedule.Values[0].id, $schedule.Values[0].properties.Interval, $actions.Values[0].properties.Name )
                }
           }
        }
        #write-host $actions.Values.properties #.Name possiamo fare match sull'alert name
    }
}

/actions?api-version=2015-03-20


$scheudles='savedSearches/{Search  ID}/schedules?api-version=2015-03-20'

$problems='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OI-Default-East-US/providers/Microsoft.OperationalInsights/workspaces/bbacc090-abbd-4313-9545-6dd72b96a1f6/sav
edSearches/daniele''''s demos|top computer avg cpu/schedules?api-version=2015-03-20'

$problems='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OI-Default-East-US/providers/Microsoft.OperationalInsights/workspaces/bbacc090-abbd-4313-9545-6dd72b96a1f6/sav
edSearches/daniele%27s+demos%7ctop+computer+avg+cpu/schedules?api-version=2015-03-20'

$test =  [System.Web.HttpUtility]::UrlEncode('daniele''s demos|top computer avg cpu')
$uri=$problems


#Azure Recovery Services
   
#https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectionContainers?api-version=2016-05-01&$filter=backupManagementType eq 'AzureIaasVM'
#https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectionContainers?api-version=2016-05-01&$filter=backupManagementType eq 'MAB'

$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectionContainers?api-version=2016-05-01&$filter=backupManagementType eq ''AzureIaasVM'''
$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectionContainers?api-version=2016-05-01&$filter=backupManagementType eq ''MAB'''


#items

# [backupManagementType](https://github.com/Azure/azure-sdk-for-net/blob/master/src/ResourceManagement/RecoveryServices.Backup/RecoveryServicesBackupManagement/Generated/Models/BackupManagementType.cs) 
namespace Microsoft.Azure.Management.RecoveryServices.Backup.Models
{
    public enum BackupManagementType
    {
        AzureIaasVM = 0,
        
        MAB = 1,
        
        DPM = 2,
        
        AzureBackupServer = 3,
    }
}

$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectedItems?api-version=2016-05-01&$filter=backupManagementType eq ''AzureIaasVM'' and itemType eq ''VM'''

$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupProtectedItems?api-version=2016-05-01&$filter=backupManagementType eq ''MAB'' and itemType eq ''FileFolder'''




$lookbackDays=15

			$now = Format-Time -utcTime ((Get-Date).ToUniversalTime())
			$then = Format-Time -utcTime (((Get-Date).ToUniversalTime()).AddDays(-$LookbackDays))
$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupJobs?api-version=2016-05-01&$filter=operation eq ''Backup'' and startTime eq ''{0}'' and endTime eq ''{1}''' -f $then, $now


$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupJobs?api-version=2016-05-01&$filter=operation eq ''Backup'' and startTime eq ''2016-04-27 03:17:43 PM'' and endTime eq ''2016-05-12 03:17:44 PM'''


$uri='https://management.azure.com/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupPolicies?api-version=2016-05-01'

  $res = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -verbose


  $uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/containers/iaasvmcontainer;pre-infrastructure;pre-webapp1/?api-version=2015-03-15'
                                    /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Backup/BackupVault/pre-weu-backup/Containers/iaasvmcontainer;pre-infrastructure;pre-webapp1/items/iaasvmcontainer;pre-infrastructure;pre-webapp1
  $uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/protectedItems?api-version=2015-03-15'
  $res = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -verbose

  $cid='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/containers/iaasvmcontainer;pre-infrastructure;pre-webapp1'
  $cItemid='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Backup/BackupVault/pre-weu-backup/registeredContainers/iaasvmcontainer;pre-infrastructure;pre-webapp1/items/iaasvmcontainer;pre-infrastructure;pre-webapp1'


  $account=Get-AzureRmAUtomationAccount -debug
  $runbooks=Get-AzureRmAUtomationRunbook -ResourceGroupName $account.ResourceGroupName -AutomationAccountName $account.AutomationAccountName -debug
  Get-AzureRmAutomationScheduledRunbook -ResourceGroupName $account.ResourceGroupName -AutomationAccountName $account.AutomationAccountName -debug
  Get-AzureRmAutomationJob -ResourceGroupName $account.ResourceGroupName -AutomationAccountName $account.AutomationAccountName -StartTime (get-date).AddDays(-7) -EndTime (Get-date) -RunbookName 'SIDOnline-Step1' -debug
  Get-AzureRmAutomationWebhook -ResourceGroupName $account.ResourceGroupName -AutomationAccountName $account.AutomationAccountName -Debug

$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks?api-version=2015-10-31'

#    {
#      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
#Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks/Tagetik-InfraAzure",
#      "location": "West Europe",
#      "name": "Tagetik-InfraAzure",
#      "type": "Microsoft.Automation/AutomationAccounts/Runbooks",
#      "properties": {
#        "runbookType": "Script",
#        "state": "Edit",
#        "logVerbose": false,
#        "logProgress": false,
#        "logActivityTrace": 1,
#        "creationTime": "2015-08-29T15:52:24.5+02:00",
#        "lastModifiedTime": "2015-09-03T12:01:35.25+02:00"
#      }
#    },

$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/schedules?api-version=2015-10-31'

<#
Comment text...
Body:
{
  "value": [
    {
      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
Microsoft.Automation/automationAccounts/PreLabsAutoWE/schedules/Test Schedule Expired",
      "name": "Test Schedule Expired",
      "properties": {
        "description": "",
        "startTime": "2016-05-28T19:15:00+02:00",
        "startTimeOffsetMinutes": 0.0,
        "expiryTime": "2017-05-28T19:15:00+02:00",
        "expiryTimeOffsetMinutes": 0.0,
        "isEnabled": true,
        "interval": 1,
        "frequency": "Hour",
        "creationTime": "2016-05-28T19:08:02.977+02:00",
        "lastModifiedTime": "2016-05-28T19:08:02.977+02:00",
        "nextRun": "2016-05-28T20:15:00+02:00",
        "nextRunOffsetMinutes": 0.0,
        "timeZone": "UTC"
      }
    },
    {
      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
Microsoft.Automation/automationAccounts/PreLabsAutoWE/schedules/Test Schedule Monthly",
      "name": "Test Schedule Monthly",
      "properties": {
        "description": "",
        "startTime": "2016-05-30T19:38:00+02:00",
        "startTimeOffsetMinutes": 0.0,
        "expiryTime": "9999-12-31T23:59:59.9999999+01:00",
        "expiryTimeOffsetMinutes": 0.0,
        "isEnabled": true,
        "interval": 1,
        "frequency": "Month",
        "creationTime": "2016-05-28T19:09:29.547+02:00",
        "lastModifiedTime": "2016-05-28T19:09:29.547+02:00",
        "nextRun": "2016-06-10T19:38:00+02:00",
        "nextRunOffsetMinutes": 0.0,
        "timeZone": "UTC"
      }
    },
    {
      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
Microsoft.Automation/automationAccounts/PreLabsAutoWE/schedules/Test Schedule Once",
      "name": "Test Schedule Once",
      "properties": {
        "description": "",
        "startTime": "2016-05-31T19:36:00+02:00",
        "startTimeOffsetMinutes": 0.0,
        "expiryTime": "2016-05-31T19:36:00+02:00",
        "expiryTimeOffsetMinutes": 0.0,
        "isEnabled": true,
        "interval": null,
        "frequency": "OneTime",
        "creationTime": "2016-05-28T19:06:46.13+02:00",
        "lastModifiedTime": "2016-05-28T19:06:46.13+02:00",
        "nextRun": "2016-05-31T19:36:00+02:00",
        "nextRunOffsetMinutes": 0.0,
        "timeZone": "UTC"
      }
    },
    {
      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
Microsoft.Automation/automationAccounts/PreLabsAutoWE/schedules/TestSchedule1",
      "name": "TestSchedule1",
      "properties": {
        "description": "",
        "startTime": "2016-05-28T19:35:00+02:00",
        "startTimeOffsetMinutes": 0.0,
        "expiryTime": "9999-12-31T23:59:59.9999999+01:00",
        "expiryTimeOffsetMinutes": 0.0,
        "isEnabled": true,
        "interval": 1,
        "frequency": "Hour",
        "creationTime": "2016-05-28T19:05:50.567+02:00",
        "lastModifiedTime": "2016-05-28T19:05:50.567+02:00",
        "nextRun": "2016-05-28T19:35:00+02:00",
        "nextRunOffsetMinutes": 0.0,
        "timeZone": "UTC"
      }
    }
  ]
}
 
#>
$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobSchedules?api-version=2015-10-31'

<#      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
#Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobSchedules/db7ab745-cb2e-4c7d-9299-24f42b274cd3",
#      "properties": {
#        "jobScheduleId": "db7ab745-cb2e-4c7d-9299-24f42b274cd3",
#        "runbook": {
#          "name": "SIDOnline-Step1"
#        },
#        "schedule": {
#          "name": "Test Schedule Expired"
#        },
#        "runOn": null,
#        "parameters": null
#      }
#    },
#>


$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobs?$filter=properties/startTime ge 2016-05-21T16:53:56 and properties/endTime le 2016-05-28T16:53:56&api-version=2015-10-31'

$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobs?$filter=properties/startTime ge 2016-05-24T16:16:15.3510498%2B00:00 and properties/endTime le 2016-05-31T16:16:15.3530499%2B00:00 and properties/runbook/name eq ''PM2''&api-version=2015-10-31'
$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobs?$filter=properties/startTime ge 2016-05-24T16:16:15%2B00:00 and properties/endTime le 2016-05-31T16:16:15%2B00:00 and properties/runbook/name eq ''PM2''&api-version=2015-10-31'
$res = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -verbose
      
#per filtrarlo per singolo Runbook ...and properties/runbook/name eq 'PM2'
# "value": [
#    {
#      "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
#Microsoft.Automation/automationAccounts/PreLabsAutoWE/jobs/64d51c47-de10-4096-ae7a-d267a24d085f",
#      "properties": {
#        "jobId": "64d51c47-de10-4096-ae7a-d267a24d085f",
#        "runbook": {
#          "name": "PM2"
#        },
#        "provisioningState": "Failed",
#        "status": "Failed",
#        "creationTime": "2016-05-26T14:41:03.827+02:00",
#        "startTime": "2016-05-26T14:43:12.51+02:00",
#        "lastModifiedTime": "2016-05-26T14:43:12.51+02:00",
#        "endTime": "2016-05-26T14:43:12.51+02:00"
#      }
#    }

$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/webhooks?api-version=2015-10-31'

 #   {
 #     "id": "/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/
#Microsoft.Automation/automationAccounts/PreLabsAutoWE/webhooks/OMS Alert Remediation d94e6e0c-99e5-48f7-9997-b5855b288a82",
#      "name": "OMS Alert Remediation d94e6e0c-99e5-48f7-9997-b5855b288a82",
#      "properties": {
#        "isEnabled": true,
#        "expiryTime": "2018-05-25T05:08:56.0134739+02:00",
#        "runbook": {
#          "name": "Reset-OMSMS"
#        },
#        "lastInvokedTime": null,
#        "runOn": "PreLabsWorkers",
#        "parameters": null,
#        "uri": null,
#        "creationTime": "2016-05-25T05:08:58.6688419+02:00",
#        "lastModifiedBy": "",
#        "lastModifiedTime": "2016-05-25T05:08:58.6688419+02:00"
#      }
#    },
#endregion

login-azurermaccount
get-azurermsubscription | out-gridview -OutputMode Single | Select-AzureRmSubscription