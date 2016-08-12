

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
[Parameter (Mandatory=$true)][string]$clientId,
[Parameter (Mandatory=$true)][string]$SubscriptionId,
[string]$Proxy,
[Parameter (Mandatory=$true)][string]$AuthBaseAddress,
[Parameter (Mandatory=$true)][string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)][string]$ADUserName,
[Parameter (Mandatory=$true)][string]$ADPassword,
[Parameter (Mandatory=$true)][string]$resourceURI,
[string]$OMSAPIVersion='2015-03-20',
[double]$Tolerance=0.5
)
 
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSAlertRuleState"
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

#TypedPropertyBag
$AlertDataType = 0
$EventDataType	= 2
$PerformanceDataType = 2
$StateDataType       = 3

$EventSource = 'Progel Script'
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

Function Get-QueryResults
{
[CmdletBinding()]
param(
[string] $query,
[datetime] $startDate,
[datetime] $endDate,
[int] $timeout,
[string] $authToken,
[string]$ResourceBaseAddress,
[string]$resourceURI,
[string]$OMSAPIVersion
)
	try {
		$QueryArray = @{query=$Query}
		$QueryArray+= @{start=('{0}Z' -f $startDate.GetDateTimeFormats('s'))}
		$QueryArray+= @{end=('{0}Z' -f $endDate.GetDateTimeFormats('s'))}
		$body = ConvertTo-Json -InputObject $QueryArray

		$uri = '{0}{1}/search?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
		$nextLink=$null
		$results=@()
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken $authToken -nextLink $nextLink -data $body -TimeoutSeconds $timeout
			$nextLink = $result.NextLink
			$results += $result.values	
		} while ($nextLink)
#we need to check for an empty result, the behavior has changed and in this case it returns a pending status
        try {
            if ($results.count -eq 1) {
                if($results.__metadata.NumberOfDocuments -eq 0) {$results=@()}
            }

        }
        catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Unexpected error checking for query results {0} on uri {1}. {2}' -f $Error[0], $query, $uri) $TRACE_WARNING
            $results=@()
        }
		return $results
	}
	catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Error querying OMS {0} for query {1} and uri {2}" -f $Error[0], $query, $uri) $TRACE_ERROR
	}
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

	$rules=@{}

$timeout=300
    $uri = '{0}{1}/savedSearches?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
	$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout
	$savedSearches=@()
	do {
		$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout
		$nextLink = $result.NextLink
		$savedSearches += $result.values	
	} while ($nextLink)

	foreach($search in $savedSearches) {
		$uri = '{0}{1}/schedules?api-version={2}' -f $ResourceBaseAddress,$search.Id,$OMSAPIVersion
		$nextLink=$null
		$schedule = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $extLink -data $null -TimeoutSeconds $timeout -ErrorAction SilentlyContinue
		if($schedule.values) {
			#take into account just the first schedule for the search maybe this needs to be changed in future
			if ($schedule.Values[0].properties.Enabled -ieq 'True') {
			   $uri = '{0}{1}/actions?api-version={2}' -f $ResourceBaseAddress,$schedule.values.id,$OMSAPIVersion
			   $nextLink=$null
			   $actions = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout #-ErrorAction SilentlyContinue
			   if ($actions.Values) {
					if ($actions.Values[0].properties.Type -ieq 'Alert') {
						$rules.Add($actions.Values[0].properties.Name, @{
							"ScheduleId"=$schedule.Values[0].id;
							"Interval"=$schedule.Values[0].properties.Interval;
                            'Throttling'= $actions.Values.properties.throttling.DurationInMinutes
							"Status"='Inactive';
							"LastAlert"='';
							"AgeMinutes"=0;
							'Link'='';
							'First5Results'=''
						})
						Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ('{0}, Interval={1}, Name={2}' -f $schedule.Values[0].id, $schedule.Values[0].properties.Interval, $actions.Values[0].properties.Name ) $TRACE_VERBOSE
					}
			   }
			}
		}
	}

	#now get the alerts in the last 24hours
	#$query='Type:Alert SourceSystem=OMS | measure count() As Count, max(TimeGenerated) As Last by AlertName'
	$query='Type:Alert SourceSystem=OMS | dedup AlertName'
	$startDate=(Get-Date).AddDays(-24)
	
	$result = Get-QueryResults -query $query -startDate $startDate -endDate (Get-Date) -timeout $timeout -authToken $connection `
		-ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
	foreach($alert in $result) {
		if(! [String]::IsNullOrEmpty($alert.AlertName)) {
			if($rules.ContainsKey($alert.AlertName)) {
				$age = (get-Date)-([datetime] $alert.TimeGenerated)
				Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ('Got Alert for {0}, Last occurrence={1}, Age={2}, Interval={3}' -f $alert.AlertName, $alert.TimeGenerated, $age.TotalMinutes, $rules.Item($alert.AlertName).Interval) $TRACE_VERBOSE
				$rules.Item($alert.AlertName).AgeMinutes=$age.TotalMinutes
				$rules.Item($alert.AlertName).LastAlert=$alert.TimeGenerated
				#add 50% to avoid unnecessary flip/flop
				if($age.TotalMinutes -le ($rules.Item($alert.AlertName).Interval*(1+$Tolerance))) {
					$rules.Item($alert.AlertName).Status='Active'
					Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ('{0} is active getting more info' -f $alert.AlertName) $TRACE_VERBOSE

					#if it's active let's populate some more info and get the query result
					$rules.Item($alert.AlertName).Link=$alert.LinkToSearchResults
					$details = Get-QueryResults -query $alert.Query -startDate ([datetime] $alert.QueryExecutionStartTime).ToUniversalTime() -endDate ([datetime] $alert.QueryExecutionEndTime).ToUniversalTime() `
						-timeout $timeout -authToken $connection -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
					$first5 = $details | select-object -First 5 | ConvertTo-Json
					$rules.Item($alert.AlertName).First5Results=$first5
				}
			}
		}
	}

	#now prepare the property bag and return
	foreach($key in $rules.Keys) {
		$bag = $g_api.CreatePropertyBag()
		$bag.AddValue("ScheduleId",$rules.Item($key).ScheduleId)
		$bag.AddValue('AlertName', $key)
		$bag.AddValue('LastAlert', $rules.Item($key).LastAlert)
		$bag.AddValue('Status', $rules.Item($key).Status)
		$bag.AddValue('AgeMinutes', $rules.Item($key).AgeMinutes)
		$bag.AddValue('Url', $rules.Item($key).Link)
		$bag.AddValue('First5', $rules.Item($key).First5Results)
		if($traceLevel -eq $TRACE_DEBUG) {$g_API.AddItem($bag)}
		$bag
	}
	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		#it breaks in exception when run insde OpsMgr and POSH IDE	
		$g_API.ReturnItems() 
	}
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_INFORMATION ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}



