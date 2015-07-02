﻿Function Import-ADALDll {
<# 
 .Synopsis
  Load Load Active Directory Authentication Library (ADAL) Assemblies

 .Description
   Load Load Active Directory Authentication Library (ADAL) Assemblies from either the Global Assembly Cache or from the DLLs located in OMSSearch PS module directory. It will use GAC if the DLLs are already loaded in GAC.

 .Example
  # Load the ADAL Dlls
   Import-ADALDll

#>
	
	$DLLPath = (Get-Module OMSSearch).ModuleBase
	$arrDLLs = @()
	$arrDLLs += 'Microsoft.IdentityModel.Clients.ActiveDirectory.dll'
	$AssemblyVersion = "2.14.0.0"
	$AssemblyPublicKey = "31bf3856ad364e35"
	$bSDKLoaded = $true

	Foreach ($DLL in $arrDLLs)
	{
		$AssemblyName = $DLL.TrimEnd('.dll')
		If (!([AppDomain]::CurrentDomain.GetAssemblies() |Where-Object { $_.FullName -eq "$AssemblyName, Version=$AssemblyVersion, Culture=neutral, PublicKeyToken=$AssemblyPublicKey"}))
		{
			Write-verbose 'Loading Assembly $AssemblyName...'
			Try {
				$DLLFilePath = Join-Path $DLLPath $DLL
				[Void][System.Reflection.Assembly]::LoadFrom($DLLFilePath)
			} Catch {
				Write-Verbose "Unable to load $DLLFilePath. Please verify if the DLLs exist in this location!"
				$bSDKLoaded = $false
			}
		}
	}
	$bSDKLoaded
}

Function Get-AADToken {
		
		[CmdletBinding()]
		PARAM (
		[Parameter(ParameterSetName='SMAConnection',Mandatory=$true)][Alias('Connection','c')][Object]$OMSConnection,
		[Parameter(ParameterSetName='IndividualParameter',Mandatory=$true)][Alias('t')][String]$TenantADName,
		[Parameter(ParameterSetName='IndividualParameter',Mandatory=$true)][Alias('u')][String]$Username,
		[Parameter(ParameterSetName='IndividualParameter',Mandatory=$true)][Alias('p')][String]$Password
		)
try {
	$ImportSDK = Import-ADALDll
	If ($ImportSDK -eq $false)
	{
		Write-Error "Unable to load ADAL DLL. Aborting."
		Return
	}
	If ($OMSConnection)
	{
		$Username       = $OMSConnection.Username
		$Password       = $OMSConnection.Password
		$TenantADName   = $OMSConnection.TenantADName

	}

	# Set well-known client ID for Azure PowerShell
	$clientId = "1950a258-227b-4e31-a9cf-717495945fc2"
	
	# Set redirect URI for Azure PowerShell
	$redirectUri = "urn:ietf:wg:oauth:2.0:oob"

	# Set Resource URI to Azure Service Management API
	$resourceAppIdURI = "https://management.core.windows.net/"

	# Set Authority to Azure AD Tenant
	$authority = "https://login.windows.net/$TenantADName"

	$credential = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential" -ArgumentList $Username,$Password
	# Create AuthenticationContext tied to Azure AD Tenant
	$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

	$authResult = $authContext.AcquireToken($resourceAppIdURI,$clientId,$credential)
	$Token = $authResult.CreateAuthorizationHeader()
	Return $Token
	}
catch {
		Write-Error "Get-AADToken error $($Error[0].Exception)"
		write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
		Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
		return $null
}

}
Function Get-OMSSavedSearch {

<# 
 .Synopsis
  Gets Saved Searches from OMS workspace

 .Description
   Gets Saved Searches from OMS workspace

 .Example
  # Gets Saved Searches from OMS. Returns results.
  $OMSCon = Get-AutomationConnection -Name 'OMSCon'
  $Token = Get-AADToken -OMSConnection $OMSCon
  $subscriptionId = "3c1d68a5-4064-4522-94e4-e0378165555e"
  $ResourceGroupName = "oi-default-east-us"
  $OMSWorkspace = "Test"	
  Get-OMSSavedSearches -SubscriptionID $subscriptionId -ResourceGroupName $ResourceGroupName  -OMSWorkspaceName $OMSWorkspace -Token $Token

#>

	[CmdletBinding()]
	PARAM (
		[Parameter(Mandatory=$true)][string]$SubscriptionID,
		[Parameter(Mandatory=$true)][String]$ResourceGroupName,
		[Parameter(Mandatory=$true)][String]$OMSWorkspaceName,
		[Parameter(Mandatory=$true)][String]$Token,
		[Parameter(Mandatory=$false)][String]$API='2015-03-20'

	)
	$uri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/savedSearches?api-version={3}" -f $SubscriptionID, $ResourceGroupName, $OMSWorkspaceName, $API
	$headers = @{"Authorization"=$Token;"Accept"="application/json"}
	$headers.Add("Content-Type","application/json")
	$result = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing
	if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
	  if($result.Content -ne $null){
		$json = (ConvertFrom-Json $result.Content)
		if($json -ne $null){
		  $return = $json
		  if($json.value -ne $null){$return = $json.value}
		}
	  }
	}

	else{
	Write-Error "Failed to egt saved searches. Check parameters."
  }
  return $return
}
Function Invoke-OMSSearchQuery {

<# 
 .Synopsis
  Executes Search Query against OMS

 .Description
   Executes Search Query against OMS

 .Example
  # Executes Search Query against OMS. Returns results from query.
  $OMSCon = Get-AutomationConnection -Name 'OMSCon'
  $Token = Get-AADToken -OMSConnection $OMSCon
  $subscriptionId = "3c1d68a5-4064-4522-94e4-e0378165555e"
  $ResourceGroupName = "oi-default-east-us"
  $OMSWorkspace = "Test"	
  $Query = "shutdown Type=Event EventLog=System Source=User32 EventID=1074 | Select TimeGenerated,Computer"
  $NumberOfResults = 150
  $StartTime = (((get-date)).AddHours(-6).ToUniversalTime()).ToString("yyyy-MM-ddTHH:mm:ss:fffZ")
  $EndTime = ((get-date).ToUniversalTime()).ToString("yyyy-MM-ddTHH:mm:ss:fffZ")
  Execute-OMSSearchQuery -SubscriptionID $subscriptionId -ResourceGroupName $ResourceGroupName  -OMSWorkspaceName $OMSWorkspace -Query $Query -Token $Token
  Execute-OMSSearchQuery -SubscriptionID $subscriptionId -ResourceGroupName $ResourceGroupName  -OMSWorkspaceName $OMSWorkspace -Query $Query -Token $Token -Top $NumberOfResults -Start $StartTime -End $EndTime

#>

	[CmdletBinding(DefaultParameterSetName="NoDateTime")]
	PARAM (
		[Parameter(Mandatory=$true,ParameterSetName="NoDateTime")][Parameter(Mandatory=$true,ParameterSetName="DateTime")][string]$SubscriptionID,
		[Parameter(Mandatory=$true,ParameterSetName="NoDateTime")][Parameter(Mandatory=$true,ParameterSetName="DateTime")][String]$ResourceGroupName,
		[Parameter(Mandatory=$true,ParameterSetName="NoDateTime")][Parameter(Mandatory=$true,ParameterSetName="DateTime")][String]$OMSWorkspaceName,
		[Parameter(Mandatory=$true,ParameterSetName="NoDateTime")][Parameter(Mandatory=$true,ParameterSetName="DateTime")][String]$Query,
		[Parameter(Mandatory=$true,ParameterSetName="NoDateTime")][Parameter(Mandatory=$true,ParameterSetName="DateTime")][String]$Token,
		[Parameter(Mandatory=$false,ParameterSetName="NoDateTime")][Parameter(Mandatory=$false,ParameterSetName="DateTime")][int]$Top,
		[Parameter(Mandatory=$true,ParameterSetName="DateTime")][ValidatePattern("\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}:\d{3}Z")][string]$Start,
		[Parameter(Mandatory=$true,ParameterSetName="DateTime")][ValidatePattern("\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}:\d{3}Z")][string]$End,
		[Parameter(Mandatory=$false)][String]$API='2015-03-20'

	)
	$uri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}/search?api-version={3}" -f $SubscriptionID, $ResourceGroupName, $OMSWorkspaceName, $API 
	$QueryArray = @{Query=$Query}
	if ($Start -and $End) { 
		$QueryArray+= @{Start=$Start}
		$QueryArray+= @{End=$End}
		}
	if ($Top) {
		$QueryArray+= @{Top=$Top}
		}
	$enc = New-Object "System.Text.ASCIIEncoding"
	$body = ConvertTo-Json -InputObject $QueryArray
	$byteArray = $enc.GetBytes($body)
	$contentLength = $byteArray.Length
	$headers = @{"Authorization"=$Token;"Accept"="application/json"}
	$headers.Add("Content-Length",$contentLength)
	$headers.Add("Content-Type","application/json")
	$result = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -Body $body -UseBasicParsing
	if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
	  if($result.Content -ne $null){
		[void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")        
		$jsonserial= New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer 
		$jsonserial.MaxJsonLength  =  [int]::MaxValue
		$json = $jsonserial.DeserializeObject($result.Content)
		if($json -ne $null){
		  $return = $json
		  if($json.value -ne $null){$return = $json.value}
		}
	  }
	}

	else{
	Write-Error "Failed to execute query. Check parameters."
  }
  return $return
}
Function Get-OMSWorkspace {
<# 
 .Synopsis
  Get OMS Workspaces

 .Description
  Get OMS Workspaces

 .Example
  $SubscriptionId = "3c1d68a5-4064-4522-94e4-e0378165555e"
  $Token = Get-AADToken -OMSConnection $OMSCon
  Get-OMSWorkspace -SubscriptionId $Subscriptionid -Token $Token

#>
	[CmdletBinding()]
	PARAM (
		[Parameter(Mandatory=$true)][string]$SubscriptionID,
		[Parameter(Mandatory=$true)][String]$Token,
		[Parameter(Mandatory=$false)][String]$API='2015-03-20'

	)
	$uri = "https://management.azure.com/subscriptions/{0}/providers/microsoft.operationalinsights/workspaces?api-version={1}" -f $SubscriptionID, $API
	$headers = @{"Authorization"=$Token;"Accept"="application/json"}
	$headers.Add("Content-Type","application/json")
	$result = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing
	if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
	  if($result.Content -ne $null){
		$json = (ConvertFrom-Json $result.Content)
		if($json -ne $null){
		  $return = $json
		  if($json.value -ne $null){$return = $json.value}
		}
	  }
	}

	else{
	Write-Error 'Failed to get OMS Workspaces. Check parameters.'
  }
  return $return
}
Function Invoke-OMSSavedSearch
{
<# 
 .Synopsis
  Return the results from a named saved search

 .Description
   Gets Saved Search results

 .Example
  # Gets Saved Searches from OMS. Returns results.
  $OMSCon = Get-AutomationConnection -Name 'OMSCon'
  $Token = Get-AADToken -OMSConnection $OMSCon
  $subscriptionId = "3c1d68a5-4064-4522-94e4-e0378165555e"
  $ResourceGroupName = "oi-default-east-us"
  $OMSWorkspace = "Test"	
  Get-OMSSavedSearches -SubscriptionID $subscriptionId -ResourceGroupName $ResourceGroupName  -OMSWorkspaceName $OMSWorkspace -Token $Token

#>

	[CmdletBinding()]
	PARAM (
		[Parameter(Mandatory=$true)][string]$SubscriptionID,
		[Parameter(Mandatory=$true)][String]$ResourceGroupName,
		[Parameter(Mandatory=$true)][String]$OMSWorkspaceName,
		[Parameter(Mandatory=$true)][String]$Token,
		[Parameter(Mandatory=$true)][String]$queryName,
		[Parameter(Mandatory=$false,ParameterSetName="NoDateTime")][Parameter(Mandatory=$false,ParameterSetName="DateTime")][int]$Top,
		[Parameter(Mandatory=$true,ParameterSetName="DateTime")][ValidatePattern("\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}:\d{3}Z")][string]$Start,
		[Parameter(Mandatory=$true,ParameterSetName="DateTime")][ValidatePattern("\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}:\d{3}Z")][string]$End,
		[Parameter(Mandatory=$false)][String]$API='2015-03-20'

	)
	$savedSearch = Get-OMSSavedSearch -SubscriptionID $SubscriptionID -ResourceGroupName $ResourceGroupName -OMSWorkspaceName $OMSWorkspaceName -Token $token -API $API
	$match = $false
	foreach($q in $savedSearch) {
		$q.Id -match '\|\s*(?<query>.*)'
		if ($matches.query -ieq $queryName) {$match=$true;break;}
	}
	if(! $match) {
		write-error "$queryName not found"
		return $null
	}
	if($top) {
		$results = Invoke-OMSSearchQuery -SubscriptionID $SubscriptionID -ResourceGroupName $ResourceGroupName -OMSWorkspaceName $OMSWorkspaceName -Token $token -Query $q.properties.Query -Top $top -API $API
	}
	elseif ($start) {
		$results = Invoke-OMSSearchQuery -SubscriptionID $SubscriptionID -ResourceGroupName $ResourceGroupName -OMSWorkspaceName $OMSWorkspaceName -Token $token -Query $q.properties.Query -Start $Start -End $End -API $API
	}
	else {$results = Invoke-OMSSearchQuery -SubscriptionID $SubscriptionID -ResourceGroupName $ResourceGroupName -OMSWorkspaceName $OMSWorkspaceName -Token $token -Query $q.properties.Query -API $API}

	return $results

}

Function Invoke-ARMGet
{
<# 
 .Synopsis

 .Description


 .Example


#>

	[CmdletBinding()]
	PARAM (
		[Parameter(Mandatory=$true)][String]$Token,
		[Parameter(Mandatory=$true)][String]$uri
	)	

	$headers = @{"Authorization"=$Token;"Accept"="application/json"}
	$headers.Add("Content-Type","application/json")
	#$uri="https://management.azure.com/subscriptions?api-version=2015-01-01"
	$result = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing
	$json=$null
	if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){
	  if($result.Content -ne $null){
		$json = (ConvertFrom-Json $result.Content)
	  }
	}
	return $json
}