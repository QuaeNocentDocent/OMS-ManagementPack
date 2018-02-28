

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
[string]$OMSAPIVersion='2015-11-01-preview',
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
$INFO_EVENT_ID = 1104

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
					foreach($action in $actions.Values) {
					if ($action.properties.Type -ieq 'Alert') {
						try {$threshold = $action.properties.Threshold} catch {$threshold=''}
						$rules.Add($action.properties.Name, @{
							"ScheduleId"=$schedule.Values[0].id;
							"Interval"=$schedule.Values[0].properties.Interval;
                            'Throttling'= $action.properties.throttling.DurationInMinutes
							"Status"='Inactive';
							"Threshold"=(ConvertTo-Json $threshold)
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
	}

	$query='Alert | where SourceSystem=="OMS" | summarize arg_max(TimeGenerated,*) by AlertName'	
	$result = Get-QNDKustoQueryResult -query $query -timespan 'P3D' -timeout $timeout -authToken $connection `
		-ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
	foreach($alert in $result) {
		if(! [String]::IsNullOrEmpty($alert.AlertName)) {
			if($rules.ContainsKey($alert.AlertName)) {
				$age = (get-Date)-([datetime] $alert.TimeGenerated) #we can avoid converting both dates to UTC since [datetime] alerady converts to localtime
				Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ('Got Alert for {0}, Last occurrence={1}, Age={2}, Interval={3}' -f $alert.AlertName, $alert.TimeGenerated, $age.TotalMinutes, $rules.Item($alert.AlertName).Interval) $TRACE_VERBOSE
				$rules.Item($alert.AlertName).AgeMinutes=$age.TotalMinutes
				$rules.Item($alert.AlertName).LastAlert=$alert.TimeGenerated
				#add 50% to avoid unnecessary flip/flop
				if($age.TotalMinutes -le ($rules.Item($alert.AlertName).Interval*(1+$Tolerance))) {
					$rules.Item($alert.AlertName).Status='Active'
					Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ('{0} is active getting more info' -f $alert.AlertName) $TRACE_VERBOSE
					$rules.Item($alert.AlertName).Link=$alert.LinkToSearchResults
					#if it's active let's populate some more info and get the query result
					if([String]::IsNullOrEmpty($rules.Item($Alert.AlertName).Threshold)) {
						$query=$alert.Query
					    $details = Get-QNDKustoQueryResult -query $query -timespan 'P3D' `
						    -timeout $timeout -authToken $connection -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
					    $first5 = $details | select-object -First 5 | ConvertTo-Json
					    $rules.Item($alert.AlertName).First5Results=$first5
					}
					else {
						try {
                            #in this version
                            # 1. get again all the alerts
                            $query=('Alert | where SourceSystem=="OMS" and AlertName=="{0}"' -f $alert.AlertName) #this needs to be changed when we will generate one alert per computer in metrics based alerts
	                        $timespan='PT{0}M' -f $rules.Item($alert.AlertName).Interval*(1+$Tolerance)
	                        $alertList = Get-QNDKustoQueryResult -query $query -timespan $timespan -timeout $timeout -authToken $connection `
		                        -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
                            $threshold = ConvertFrom-Json  $rules.Item($Alert.AlertName).Threshold
							if ($threshold.MetricsTrigger) {								
                                Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -level $TRACE_VERBOSE -msg ('Getting details from metrics')
								if ($threshold.Operator -ieq 'gt') {$op='>'} else {$op='<'}
								$queryTemplate = '{0} | where Computer=="{3}" and AggregatedValue {1} {2} and TimeGenerated>{4} and TimeGenerated<{5}'
                                #for each active alert get the actual value
                                foreach($metricAlert in $alertList) {
                                    $query = ($queryTemplate -f $Alert.Query, $op, $threshold.Value, $metricAlert.Computer, ([datetime] $alert.QueryExecutionStartTime).ToUniversalTime(), ([datetime]$alert.QueryExecutionEndTime).ToUniversalTime())
					                $details = Get-QNDKustoQueryResult -query $query -timespan 'P3D' `
						                -timeout $timeout -authToken $connection -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion
                                    $rules.Item($alert.AlertName).First5Results+=(ConvertTo-Json $details[0])
                                }
							}
							else {$rules.Item($alert.AlertName).First5Results+=(ConvertTo-Json $alert)}
						}
						catch {
                            Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_WARNING -level $TRACE_WARNING -msg ('Error getting details for alert {0}. {1}' -f $alert.AlertName, $Error[0])
                        }
					}
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



