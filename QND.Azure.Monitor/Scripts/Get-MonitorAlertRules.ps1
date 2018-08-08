## This discovery needs to be splitted 'cause potentially can discover a huge number of entities, the disocvery rule is disabled by default
## Gorup memeberhsip must be changed and split in diffrent rules using the properties we're setting

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/
#*************************************************************************
# Script Name - 
# Author	  -  Daniele Grandini - QND
# Version	  - 1.0 30-04-2016
# Purpose     - 
#               
# Assumptions - 
#				
#               
# Parameters  - TraceLevel
#             - ComputerName
#				- SourceId
#				- ManagedEntityId
# Command Line - .\test.ps1 4 "serverName" '{1860E0EB-8C21-41DA-9F35-2FE9343CCF36}' '{1860E0EB-8C21-41DA-9F35-2FE9343CCF36}'
# If discovery must be added the followinf parameters
#				SourceId ($ MPElement $ )
#				ManagedEntityId ($ Target/Id $)
#
# Output properties
#
# Status
#
# Version History
#	  1.0 06.08.2010 DG First Release
#     1.5 15.02.2014 DG minor cosmetics
#
# (c) Copyright 2010, Progel srl, All Rights Reserved
# Proprietary and confidential to Progel srl              
#
#*************************************************************************


# Get the named parameters
param([int]$traceLevel=2,
[Parameter (Mandatory=$true)] [string]$sourceID,
[Parameter (Mandatory=$true)] [string]$ManagedEntityId,
[Parameter (Mandatory=$true)][string]$clientId,
[Parameter (Mandatory=$true)][string]$SubscriptionId,
[string]$Proxy,
[Parameter (Mandatory=$true)][string]$AuthBaseAddress,
[Parameter (Mandatory=$true)][string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)][string]$ADUserName,
[Parameter (Mandatory=$true)][string]$ADPassword,
[string]$Exclusions=$null
)
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "QND.Get-MonitorAlertRules"
$SCRIPT_VERSION = "1.0"

#Trace Level Costants
$TRACE_NONE 	= 0
$TRACE_ERROR 	= 1
$TRACE_WARNING = 2
$TRACE_INFO 	= 3
$TRACE_VERBOSE = 4
$TRACE_DEBUG = 5

#Event Type Constants
$EVENT_TYPE_SUCCESS      = 0
$EVENT_TYPE_ERROR        = 1
$EVENT_TYPE_WARNING      = 2
$EVENT_TYPE_INFORMATION  = 4
$EVENT_TYPE_AUDITSUCCESS = 8
$EVENT_TYPE_AUDITFAILURE = 16

#Standard Event IDs
$FAILURE_EVENT_ID = 4000		#errore generico nello script
$SUCCESS_EVENT_ID = 1101
$START_EVENT_ID = 1102
$STOP_EVENT_ID = 1103
$INFO_EVENT_ID = 1105

#TypedPropertyBag
$AlertDataType = 0
$EventDataType	= 2
$PerformanceDataType = 2
$StateDataType       = 3

$EventSource = 'QND Script'
$EventLog= 'Operations Manager'
#endregion

#region Logging

if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
    [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $eventlog)
}

function Log-Params
{
    param($Invocation)
    $line=''
    foreach($key in $Invocation.BoundParameters.Keys) {$line += "$key=$($Invocation.BoundParameters[$key])  "}
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFORMATION  ("Starting script. Invocation Name:$($Invocation.InvocationName)`n Parameters`n $line") $TRACE_INFO
}

function Create-Event
  {
    param(
    [int] $eventID, 
    [int] $eventType,
    [string] $msg,
    [string[]] $parameters)

    switch ($eventType) {
        $EVENT_TYPE_SUCCESS {$nativeType=[System.Diagnostics.EventLogEntryType]::Information}
        $EVENT_TYPE_ERROR {$nativeType=[System.Diagnostics.EventLogEntryType]::Error}
        $EVENT_TYPE_WARNING {$nativeType=[System.Diagnostics.EventLogEntryType]::Warning}
        $EVENT_TYPE_INFORMATION {$nativeType=[System.Diagnostics.EventLogEntryType]::Information}
        $EVENT_TYPE_AUDITSUCCESS {$nativeType=[System.Diagnostics.EventLogEntryType]::AuditSuccess}
        $EVENT_TYPE_AUDITFAILURE {$nativeType=[System.Diagnostics.EventLogEntryType]::AuditFailure}
        default {
            Write-Verbose 'match?'
            $nativeType=[System.Diagnostics.EventLogEntryType]::Information
        }
    }
    $event = New-Object System.Diagnostics.EventInstance($eventID,1,$nativeType)

    $evtObject = New-Object System.Diagnostics.EventLog;
    $evtObject.Log = $EventLog;
    $evtObject.Source = $EventSource;
    $parameters = @($msg) + $parameters
    $evtObject.WriteEvent($event, $parameters)
  }


function Log-Event
{
	param($eventID, $eventType, $msg, $level)
	
	Write-Verbose ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
	if($level -le $P_TraceLevel)
	{
		Write-Host ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
        Create-Event -eventID $eventID -eventType $eventType -msg ($msg + "`n" + "Version :" + $SCRIPT_VERSION) -parameters @($SCRIPT_NAME,$SCRIPT_VERSION)
		#$g_API.LogScriptEvent($SCRIPT_NAME,$eventID,$eventType, ($msg + "`n" + "Version :" + $SCRIPT_VERSION))
	}
}
#endregion

#region Discovery Helpers
Function Throw-EmptyDiscovery
{
	param($SourceId, $ManagedEntityId)

	$oDiscoveryData = $g_API.CreateDiscoveryData(0, $SourceId, $ManagedEntityId)
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING "Exiting with empty discovery data" $TRACE_INFO
	$oDiscoveryData
	If($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent
		$g_API.Return($oDiscoveryData)
	}
}

Function Throw-KeepDiscoveryInfo
{
param($SourceId, $ManagedEntityId)
	$oDiscoveryData = $g_API.CreateDiscoveryData(0,$SourceId,$ManagedEntityId)
	#Instead of Snapshot discovery, submit Incremental discovery data
	$oDiscoveryData.IsSnapshot = $false
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING "Exiting with null non snapshot discovery data" $TRACE_INFO
	$oDiscoveryData    
	If($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		$g_API.Return($oDiscoveryData)
	}
}

#endregion

Function Import-ResourceModule
{
	param($moduleName, $ArgumentList=$null)
	if (Get-Module -Name $moduleName) {return}

	$moduleName = '{0}.psm1' -f $moduleName
	$ResPath = (get-itemproperty -path 'HKLM:\system\currentcontrolset\services\healthservice\Parameters' -Name 'State Directory').'State Directory' + '\Resources'
	if(Test-Path $ResPath) {
		$module = @(get-childitem -path $ResPath -Filter $moduleName -Recurse)[0]
	}
	if($module) { $module = $module.FullName}
	else {$module = "$PSScriptRoot\$moduleName"}

	If (Test-Path $module) {Import-Module -Name $module -ArgumentList $ArgumentList}
	else {Throw [System.DllNotFoundException] ('{0} not found' -f $module)}
}

Function Discover-AlertRule
{
	param($Id, $AlertName, $AlertDescription, $AlertType, $Location, $AlertKind, $SubscriptionId)

	$displayName=('{0}' -f $AlertName)
	if([String]::IsNullOrEmpty($AlertDescription)) {$AlertDescription='n.a.'}
	$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']$")	
	$objInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.Subscription']/SubscriptionId$", $SubscriptionId)
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.Class']/SubscriptionId$", $SubscriptionId)	
	$decodedId=[System.Web.HttpUtility]::UrlDecode($Id) #try not to use this
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Id$", $Id)	
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Type$", $AlertType)	
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Name$", $AlertName)	
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Location$", $Location)	
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Kind$", $AlertKind)	
	$objInstance.AddProperty("$MPElement[Name='QND.Azure.Monitor.AlertRule.Class']/Description$", $AlertDescription)	
	$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $DisplayName)	
	$discoveryData.AddInstance($objInstance)	
    Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -level $TRACE_VERBOSE -msg ('Posting discovery data for ''{0}'' type {2} for subscription {1} with id {3}' -f $AlertName, $SubscriptionId, $AlertType, $Id)
}

Function GetMetricsRule
{
	[OutputType([array])]
	param(
		$SubscriptionId,
		$timeout,
		$connection
	)
	$rules=@()
	$metricAlertsAPI='2018-03-01'
	$uri=('https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/metricAlerts?api-version={1}' -f $subscriptionId,$metricAlertsAPI)
	$nextLink=$null
	$body=$null
	do {
		$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)	
		if($result.StatusCode -ne 200) {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Error getting Metric Rules $Error") $TRACE_ERROR
		}
		write-verbose ('Got {0} metric rules' -f $result.values.count)
		if($result.GotValue) {
			foreach($rule in $result.Values) {
				if($rule.properties.Enabled) {
					$rules+= New-Object -TypeName PSCustomObject -Property @{
						Id = $rule.Id
						Name=$rule.Name
						Type=$rule.Type
						Description = $rule.properties.Description
						Kind = 'unknown'
						Location = $rule.Location
					}
					#Discover-AlertRule -Id $rule.Id -AlertName $rule.Name -AlertType $rule.Type -AlertDescription $rule.properties.Description -AlertKind 'unknown' -Location $rule.Location -SubscriptionId $SubscriptionId
				}
			}
		}
	} while ($nextLink)	
	return $rules
}

Function GetActivityLogRules
{	
	[OutputType([array])]
	param(
		$SubscriptionId,
		$timeout,
		$connection
	)
	$rules=@()
	$activityLogAPI='2017-04-01'
	
	$uri=('https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/activityLogAlerts?api-version={1}' -f $subscriptionId,$activityLogAPI)

	$nextLink=$null
	$body=$null
	do {
		$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
		if($result.StatusCode -ne 200) {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Error getting activity log Rules $Error") $TRACE_ERROR
		}
		write-verbose ('Got {0} activity log rules' -f $result.values.count)
		if($result.GotValue) {		
			foreach($rule in $result.Values) {
				if($rule.properties.Enabled) {
					$rules+= New-Object -TypeName PSCustomObject -Property @{
						Id = $rule.Id
						Name=$rule.Name
						Type=$rule.Type
						Description = $rule.properties.Description
						Kind = $rule.Kind
						Location = $rule.Location
					}
				}
			}
		}
	} while ($nextLink)
	return $rules
}

Function GetLogRules
{
	[OutputType([array])]
	param(
		$SubscriptionId,
		$timeout,
		$ResourceBaseAddress,
		$connection
	)
	$rules=@()
		#first discover all the log analytics workspaces in the subscription
		$uri = '{0}/subscriptions/{1}/resources?$filter=resourceType EQ ''Microsoft.OperationalInsights/workspaces''&api-version=2016-09-01' -f $ResourceBaseAddress, $SubscriptionId
		$nextLink = $null
		$OMSAPIVersion='2015-03-20'
		$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
		foreach($workspace in $result.Values) {
			$resourceGroup=($workspace.id -split '/')[4]
			$resourceURI=$workspace.Id
	
			$uri = '{0}{1}/savedSearches?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
			$nextLink = $null
			$savedSearches=@()
			do {
				$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
				$nextLink = $result.NextLink
				$savedSearches += $result.values	
			} while ($nextLink)
			write-verbose ('Got {0} saved searches' -f $savedSearches.count)
	
			foreach($search in $savedSearches) {
				$uri = '{0}{1}/schedules?api-version={2}' -f $ResourceBaseAddress,$search.Id,$OMSAPIVersion
				$nextLink=$null
				$schedule = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $extLink -data $null -TimeoutSeconds $timeout -ErrorAction SilentlyContinue -Verbose:($PSBoundParameters['Verbose'] -eq $true)
				if($schedule.values) {			
					#take into account just the first schedule for the search maybe this needs to be changed in future
					if ($schedule.Values[0].properties.Enabled -ieq 'True') {
					   $uri = '{0}{1}/actions?api-version={2}' -f $ResourceBaseAddress,$schedule.values[0].id,$OMSAPIVersion
					   $nextLink=$null			   
					   $actions = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)				   
					   if ($actions.Values) {
							foreach($action in $actions.Values) {
								if ($action.properties.Type -ieq 'Alert') {
									$alertType='Standard'
									try { if($action.properties.Threshold.MetricsTrigger) {$alertType='MetricBased'}} catch {}
									if ([String]::IsNullOrEmpty($action.properties.Description)) {$AlertDescription='n.a.'} else {$alertDescription=$action.properties.Description}
									$rules+= New-Object -TypeName PSCustomObject -Property @{
										Id = $schedule.Values[0].id
										Name=$action.properties.Name
										Type='Microsoft.OperationalInsights'
										Description = $AlertDescription
										Kind = $alertType
										Location = 'n.a.'
									}
								}
							}
					   }
					}
				}
			}
			
		}
		return $rules
}
#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date
	$P_TraceLevel = $traceLevel
	Log-Params $MyInvocation

	try {
		Import-ResourceModule -moduleName QNDAdal -ArgumentList @($false)
		Import-ResourceModule -moduleName QNDAzure
	}
	catch {
		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Cannot load required powershell modules $Error") $TRACE_ERROR
		exit 1	
	}

try
{
	if($proxy) {
		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Proxy is not currently supported {0}" -f $proxy) $TRACE_WARNING
	}
	$pwd = ConvertTo-SecureString $ADPassword -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential ($ADUserName, $pwd)
	$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $cred
	$connection = $authority.CreateAuthorizationHeader()
}
catch {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Cannot get Azure AD connection aborting $Error") $TRACE_ERROR
	Throw-KeepDiscoveryInfo
	exit 1	
}

try {
	$timeout=300
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)

	$error.clear() #let's use this like a catch all
	$rules=@()
	#first discover metrics
	[array] $rules = [array] (GetMetricsRule -SubscriptionId $SubscriptionId -timeout $timeout -connection $connection)

	#then discovery Activity Log Alerts
	$rules += [array] (GetActivityLogRules -SubscriptionId $SubscriptionId -timeout $timeout -connection $connection)

	#last discover Log rules
	$rules += [array] (GetLogRules -SubscriptionId $SubscriptionId -timeout $timeout -ResourceBaseAddress $ResourceBaseAddress -connection $connection)

	foreach($rule in $rules) {
		Discover-AlertRule -Id $rule.id -AlertName $rule.Name -AlertDescription $rule.Description -AlertType $rule.Type -AlertKind $rule.Kind -Location $rule.Location -SubscriptionId $SubscriptionId
	}
	
	$discoveryData
	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		#it breaks in exception when run insde OpsMgr and POSH IDE	
		$g_API.Return($discoveryData)
	}
	if($error) {throw $Error[0]}
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_INFORMATION ("$SCRIPT_NAME has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}



