

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
[string]$APIVersion='2015-10-31',
[Parameter (Mandatory=$false)][int]$Heartbeat=11,
[Parameter (Mandatory=$false)] [int]$timeoutSeconds=300,

    [Parameter (Mandatory=$false)] [double]$tolerance=0.5,
    [Parameter (Mandatory=$false)] [int]$onlySJWH=1,
    [Parameter (Mandatory=$false)] [int]$lookbackDays=-45,
	[Parameter (Mandatory=$false)] [int]$LastnJobs=5,
	[Parameter (Mandatory=$false)] [int]$MaxFailures=0,
	[Parameter (Mandatory=$false)] [String]$FailureCondition='^Failed|Suspended$',
	[Parameter (Mandatory=$false)] [int]$MaxAge=-1,
	[Parameter (Mandatory=$false)] [int]$MaxRuntime=-1,
	[Parameter (Mandatory=$false)] [int]$WebHookExpirationDays=-1,
	[Parameter (Mandatory=$false)] [int]$WebHookExpirationSilence=30


)

 
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSRunbookStatus"
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
	$obfuscate='pass|cred'
    foreach($key in $Invocation.BoundParameters.Keys) {
		if($key -imatch $obfuscate -and $TraceLevel -le $TRACE_INFO) {$line += ('-{0} [{1}] ' -f $key, 'omissis')}
		else {$line += ('-{0} {1} ' -f $key, $Invocation.BoundParameters[$key])}
	}
	$line += ('- running as {0}' -f (whoami))
	Log-Event -eventID $START_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ("Starting script [{0}]. Invocation Name:{1}`n Parameters`n{2}" -f $SCRIPT_NAME, $Invocation.InvocationName, $line) -level $TRACE_INFO
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

Function Get-AutomationItems
{
param(
	$uris, $connection, $bnoLink=$false
)

	$items=@()
	foreach($uri in $uris) {
		$nextLink=$null
		Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_SUCCESS ("Getting items $uri") $TRACE_VERBOSE
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken $connection -nextLink $nextLink -TimeoutSeconds $timeoutSeconds
			$nextLink = $result.NextLink
			if($result.gotValue) {$items+=$result.Values}
            if($bnolink) {$nextLink=$null}
			#hacking some unwanted chars
            if($nextLink) {$nextLink=$nextLink.Replace('+','%2B')}
		} while ($nextLink)
	}
	return $items
}

Function Return-Bag
{
    param($object, $key)
    try {    
		$bag = $g_api.CreatePropertyBag()
        foreach($property in $object.Keys) {
		    $bag.AddValue($property, $object[$property])
        }
        $bag

		if($traceLevel -eq $TRACE_DEBUG) {
			$g_API.AddItem($bag)
			$object.Keys | %{write-verbose ('{0}={1}' -f $_,$object[$_]) -Verbose}
		}
		

		Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
			-msg ('{0} - returned status bag ' `
				-f $object[$key]) `
			-level $TRACE_VERBOSE 
    }
    catch {
		Log-Event -eventID $FAILURE_EVENT_ID -eventType $EVENT_TYPE_WARNING `
			-msg ('{0} - error creating status bag {1}' `
				-f $object[$key]), $_.Message `
			-level $TRACE_VERBOSE 
    }
}


#region Common
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
	Log-Event -eventID $FAILURE_EVENT_ID -eventType $EVENT_TYPE_ERROR -msg ("Cannot logon to AzureAD error: {0} for {2} on Subscription {1}" -f $Error[0], $SubscriptionId, $resourceURI) -level $TRACE_ERROR	
	Throw-KeepDiscoveryInfo
	exit 1	
}
#endregion

try {



	$uris =@(('{0}{1}/runbooks?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion))
	$runBooks = Get-AutomationItems -uris $uris -connection $connection

<#
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
#>

    $uris=@(
        ('{0}{1}/webhooks?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
    )
    $webhooks = (Get-AutomationItems -uris $uris -connection $connection) | where {$_.properties.IsEnabled}


 <#   {
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
#    }
#>

    $uris=@(
        ('{0}{1}/schedules?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
    )
    $schedules = (Get-AutomationItems -uris $uris -connection $connection) | where {$_.properties.frequency -ine 'OneTime' -and $_.properties.isEnabled}
    
    [array] $validSchedules=@()
    foreach($s in $schedules) {
        if ($s.properties.expiryTime.Substring(0,4) -eq '9999') {$validSchedules+=$s.Name; continue}
        if ([datetime]$s.properties.expiryTime -gt (Get-Date)) {$validSchedules+=$s.Name; continue}
        #$schedules.Remove($s)
    }

    write-verbose ('Got {0} schedules, valid {1}' -f $schedules.count, $validSchedules.Count)
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

    $uris=@(
        ('{0}{1}/jobSchedules?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
    )


    #remove OneTime schedules aka keep valid schedules
    $jobSchedules = (Get-AutomationItems -uris $uris -connection $connection) | where {$_.properties.schedule.name -iin $validSchedules}
    write-verbose ('Got {0} schedules for jobs' -f $jobSchedules.count)

    $jobSchedules | %{write-verbose $_.properties}
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


    write-verbose ('About to process {0} runbooks' -f $runbooks.count)

    foreach($rb in $runbooks) {
        write-verbose ('Processing {0}' -f $rb.name)
        try {
        $wh = $webhooks | where {$_.properties.runbook.name -eq $rb.name}
        $jsch = $jobSchedules | where {$_.properties.runbook.name -ieq $rb.name}
        if($jsch) {
            write-verbose 'Runbook has schedules'
            $sch=@()
            foreach($js in $jsch) {
                $sch += $schedules | where {$_.name -eq $js.properties.schedule.name}
            }
        }
        if($onlySJWH -and !$wh -and !$jsch) {continue}
        write-verbose ('Runbook {0} has webhook or valid schedule' -f $rb.name)
        [double]$autoAge=24*32 #24 H * 32 days tot ake into account monthly schedules
<#
Request body for weekly: 
{
“name”: “ScheduleName”
“properties”: {
“description”: “”,
“startTime”: “2016-05-17T02:01:49.755565Z”,
“interval”: 1,
“frequency”: “Week”,
“timeZone”: “UTC”,
“advancedSchedule”: {
“weekDays”:[“Tuesday”]
}
}
}
Month days: 
{
“name”: “ScheduleName”
“properties”: {
“description”: “”,
“startTime”: “2016-05-17T02:01:49.755565Z”,
“interval”: 1,
“frequency”: “Month”,
“timeZone”: “UTC”,
“advancedSchedule”: {
“monthDays”:[1, 2, 4]
}
}
}
Month week day occurrence: 
{
“name”: “ScheduleName”
“properties”: {
“description”: “”,
“startTime”: “2016-05-17T02:01:49.755565Z”,
“interval”: 1,
“frequency”: “Month”,
“timeZone”: “UTC”,
“advancedSchedule”: {
“monthlyOccurences”:[
{
“occurrence”: 2, 
“day”: “Friday”
}
]
}
}
}

#>
        if($jsch) {
            #we can have multiple schedules so let's try to get the stricter one            
            foreach($s in $sch) {
                switch ($s.properties.frequency) {
                'Hour' {if($autoAge -gt $s.properties.interval) {$autoAge=$s.properties.interval}}
				'Day' {if($autoAge -gt $s.properties.interval*24) {$autoAge=$s.properties.interval*24}}
				'Week' {
					$worstCase = 7
					if($s.properties.advancedSchedule.weekDays) {
						$worstCase = 8 - $s.properties.advancedSchedule.weekDays.Count
					}
					if($autoAge -gt $s.properties.interval*$worstCase*24) {$autoAge=$s.properties.interval*$worstCase*24}
				}
                'Month' {
					$worstCase=31
					if($s.properties.advancedSchedule.monthDays) {
						$worstCase = 31 - $s.properties.advancedSchedule.monthDays.Count
					}
					if($s.properties.advancedSchedule.monthlyOccurences) {
						$worstCase = 31 - $s.properties.advancedSchedule.monthlyOccurences.Count
					}
					if($autoAge -gt $s.properties.interval*$worstCase*24) {$autoAge=$s.properties.interval*$worstCase*24}
				}
                default {
                    Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_WARNING `
				    -msg ('Unknown schedule frequency {0}' `
					    -f $s.properties.frequency) `
				    -level $TRACE_WARNING }
                }
            }
            $autoAge=$autoage*(1+$tolerance)
        }
        if ($lookbackDays -gt 0) {$from = (Get-Date).ToUniversalTime().AddDays(-$LookbackDays).GetDateTimeFormats('s')[0]}
        else {$from = (Get-Date).ToUniversalTime().AddHours(-$AutoAge*$LastnJobs).GetDateTimeFormats('s')[0]}
        $to = (Get-Date).ToUniversalTime().GetDateTimeFormats('s')[0]
	    
        write-verbose ('From {0} to {1}' -f $from, $to)

		#now it's much fater to return the last 100 jobs insetad of specifying a selection based on creationTime, so let's do it
	    $uris=@(
		    #('{0}{1}/jobs?api-version={2}&$filter=properties/startTime ge {3}%2B00:00 and properties/endTime le {4}%2B00:00 and properties/runbook/name eq ''{5}''' -f $ResourceBaseAddress,$resourceURI,$APIVersion, $from, $to, $rb.name)
			#('{0}{1}/jobs?api-version={2}&$filter=properties/creationTime ge {3}%2B00:00 and properties/runbook/name eq ''{5}''' -f $ResourceBaseAddress,$resourceURI,$APIVersion, $from, $to, $rb.name)
			('{0}{1}/jobs?api-version={2}&$filter=properties/runbook/name eq ''{5}''' -f $ResourceBaseAddress,$resourceURI,$APIVersion, $from, $to, $rb.name)
	    )
        $jobs = Get-AutomationItems -uris $uris -connection $connection -bnoLink $true | sort-object @{Expression={[datetime]$_.properties.creationTime};Descending=$true}
        $lastJobs = $jobs | Select-Object -First $LastnJobs

		$lastjobs | % {Write-Verbose ('{0} -{1}' -f $_.Name, $_.properties.status)}

        $failures = ($lastJobs | where {$_.properties.status -imatch $failureCondition}).count
		#get last completed job
        $lastCompletedJob=$null
		$runningJob=$null
		if($jobs.count -gt 0) {$lastCompletedJob = $jobs | where {$_.properties.endTime} | Select-Object -First 1}
		if($jobs.count -gt 0) {
			#for semplicity let's assume that if we have a runhning job it is the last one
			if($jobs[0].properties.startTime -and ($jobs[0].properties.endTime -eq $null)) {$runningJob=$jobs[0]}
		}

        write-verbose ('Got {0} jobs, selected {1} jobs' -f $jobs.count, $lastJobs.Count)
        if ($jobs.Count -eq 0 -or (!$lastCompletedJob -and !$runningJob)) {
            $runtimeMin=0
            $lastRuntimeMin=0
            $lastRunAgeHours=9999
            $activationTimeSec=0
            $runtimeError=$false
            $lastJobStatus='unknown'
            Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_WARNING `
			-msg ('No jobs returned or no job completed or still running for {0}' `
				-f $rb.name) `
			-level $TRACE_WARNING 

        }
        else {
			#if we don't have a completed job, for stats sake set it to the running job
			if(! $lastCompletedJob) {$lastCompletedJob=$runningJob; Write-Verbose 'No completed job, going for running'}
            $lastRunAgeHours=0
            write-verbose ('Job Endtime {0}' -f $lastCompletedJob.properties.endTime)

            #if(! $lastJobs[0].properties.endTime -or [datetime]$lastJobs[0].properties.endTime -gt (Get-Date)) {$lastCompletedJob=1;write-verbose 'Last job still running'}
            try {
                $lastJobStatus=$lastCompletedJob.properties.status
                $runtimeMin = ([datetime]$lastCompletedJob.properties.endTime - [datetime]$lastCompletedJob.properties.startTime).TotalMinutes
                if ($runningJob) {
                    $lastRuntimeMin = ((Get-Date)- [datetime]$runningJob.properties.startTime).TotalMinutes
                    $lastRunAgeHours=0
                }
                else {
                    $lastRuntimeMin=$runtimeMin
                    $lastRunAgeHours = ((Get-Date) - [datetime]$lastCompletedJob.properties.endTime).TotalHours
                }
                $activationTimeSec =([datetime] $lastCompletedJob.properties.startTime - [datetime]$lastCompletedJob.properties.creationTime).TotalSeconds      
                $longRunning=0
                if($MaxRuntime -gt -1) {if ($lastRuntimeMin -gt $MaxRuntime) {$longRunning=1}}       
            }
            catch {
			    Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_WARNING `
				    -msg ('Error getting execution time for runbook {0}' `
					    -f $rb.Name) `
				    -level $TRACE_WARNING             
            }
        }
        $obsolete=0
		$calcMaxAge=$MaxAge
        if($jsch) {
            if ($calcMaxAge -le 0 ) {$calcMaxAge=$autoAge}
            if($lastRunAgeHours -gt $calcMaxAge) {$obsolete=1}
            else {$obsolete=0}
        }
        $webHookStatus='OK'
        $daysToExpiration=365
        if($WebHookExpirationDays -gt -1) {
            foreach($w in $wh) {
			    $daysToExpiration = ([datetime]($w.properties.ExpiryTime) - (Get-Date)).TotalDays
                if ($daysToExpiration -gt (-$WebHookExpirationSilence)) {continue;} #skip old ones
                if ($daysToExpiration -le 0) {$webHookStatus='EXPIRED';break;}
			    if($daysToExpiration -le $WebHookExpirationDays) {$WebHookStatus='EXPIRESOON'}            
            }
        }
        $output=@{
            runbookId=$rb.Id;
            runbookName=$rb.Name;
            runbookType=$rb.properties.runbookType;
            lastJobStatus=$lastJobStatus;
            jobFailures=$failures;
            lastCompletedRuntimeMin=$runtimeMin;
            maxRuntime=$MaxRuntime;
            lastRuntimeMin=$lastRuntimeMin;
            lastRunAgeHours=$lastRunAgeHours;
            lastActivationTimeSec=$activationTimeSec;
            webHookStatus=$webHookStatus;
            webHookDaysToExpiration=$daysToExpiration;
            lastRunObsolete=$obsolete;
            maxAge=$calcMaxAge;
            longRunning=$longRunning;
            autoAge=$autoAge;
            lastnJobs=$LastnJobs;
            maxFailures=$MaxFailures
        }
        #ConvertTo-Json $output
        Return-Bag -object $output -key runbookName
        }
        catch {
            Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error getting stats for item {0} - {1}' -f $Item.Name, $Error[0]) $TRACE_WARNING	
            write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
            Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
            continue;
        }
    }

    if($heartBeat) {
    write-verbose 'heartbeat'
	    Create-Event -eventID $heartBeat -eventType $EVENT_TYPE_INFORMATION -level -1 -msg ('{0} running for {1}' -f $SCRIPT_NAME, $resourceURI) -parameters @($resourceURI)
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
		Log-Event -eventID $FAILURE_EVENT_ID -eventType $EVENT_TYPE_ERROR -msg ("Main got error: {0} for {2} on Subscription {1}" -f $Error[0], $SubscriptionId, $resourceURI) -level $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}

