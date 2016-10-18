

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/

#*************************************************************************
# Script Name - Get-AutomationRunbookStatus
# Author	  - Daniele Grandini - Progel spa
# Version  - 1.0 21/10/2015
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
# 1.0 History
#
# (c) Copyright 2015, Progel spa, All Rights Reserved
# Proprietary and confidential to Progel spa              
#
#*************************************************************************


# Get the named parameters
param(
	[Parameter (Mandatory=$True)] [int]$traceLevel,
	[Parameter (Mandatory=$true)] [String]$TenantADName,
	[Parameter (Mandatory=$True)] [String]$AccountId,
	[Parameter (Mandatory=$true)] [String]$Username,
	[Parameter (Mandatory=$true)] [String]$Password,
	[Parameter (Mandatory=$false)] [String]$Proxyurl, #nyi
	[Parameter (Mandatory=$false)] [int]$LastnJobs=5,
	[Parameter (Mandatory=$false)] [int]$MaxFailures=0,
	[Parameter (Mandatory=$false)] [String]$FailureCondition='^[4|9]$',
	[Parameter (Mandatory=$false)] [int]$MaxAge=-1,
	[Parameter (Mandatory=$false)] [int]$MaxRuntime=-1,
	[Parameter (Mandatory=$false)] [String]$RunbookId,
	[Parameter (Mandatory=$false)] [int]$WebHookExpirationDays=-1,
	[Parameter (Mandatory=$false)] [int]$WebHookExpirationSilence=30,
	[Parameter (Mandatory=$false)] [String]$RunMode='Data'
)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants
#Constants used for event logging
$SCRIPT_NAME			= "Get-AutomationRunbookStatus"
$SCRIPT_ARGS = 15
$SCRIPT_STARTED			= 831
$PROPERTYBAG_CREATED	= 832
$SCRIPT_ENDED			= 835
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
#endregion

#region Helper Functions
function Log-Params
{
	param($Invocation)
	$line=''
	foreach($key in $Invocation.BoundParameters.Keys) {$line += "$key=$($Invocation.BoundParameters[$key])  "}
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFORMATION  ("Starting script. Invocation Name:$($Invocation.InvocationName)`n Parameters`n $line") $TRACE_INFO
}


function Log-Event
{
	param($eventID, $eventType, $msg, $level)
	
	Write-Verbose ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
	if($level -le $P_TraceLevel)
	{
		Write-Host ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
		$g_API.LogScriptEvent($SCRIPT_NAME,$eventID,$eventType, ($msg + "`n" + "Version :" + $SCRIPT_VERSION))
	}
}

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

Function Throw-StatusBagError
{
	$bag = $g_api.CreatePropertyBag()
	$bag.AddValue("QNDType","Status")
	$bag.AddValue("Status","Error")
	$bag.AddValue("Description","$Error")
	$bag	
}

$automationURI='https://s2.automation.ext.azure.com/api/Orchestrator'
#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date
	$P_TraceLevel = $traceLevel
	Log-Params $MyInvocation

#region LoadModules
try {
	$ResPath = (get-itemproperty -path 'HKLM:\system\currentcontrolset\services\healthservice\Parameters' -Name 'State Directory').'State Directory' + '\Resources'
	if(Test-Path $ResPath) {
		$module = @(get-childitem -path $ResPath -Name OMSSearch.psm1 -Recurse)[0]
	}
	if($module) { $OMSSearchModule = "$ResPath\$module"}
	else {$OMSSearchModule = '.\OMSSearch.psm1'}
    if(! (Get-MOdule -Name OMSSearch)) {
	    If (Test-Path $OMSSearchModule) {Import-Module $OMSSearchModule}
	    else {Throw [System.DllNotFoundException] 'OMSSearch.psm1 not found'}
    }

#now load the AAD client resource. The module I'm using assumes the assembly is in the same directory of the module, but OpsMgr resource deployment uses 2 different folders

	$AssemblyName = 'Microsoft.IdentityModel.Clients.ActiveDirectory'
	$AssemblyVersion = "2.14.0.0"
	$AssemblyPublicKey = "31bf3856ad364e35"

	$DLLPath = "$ResPath\"+@(get-childitem -path $ResPath -Name "$($AssemblyName).dll" -Recurse)[0]
	If (!([AppDomain]::CurrentDomain.GetAssemblies() |Where-Object { $_.FullName -eq "$AssemblyName, Version=$AssemblyVersion, Culture=neutral, PublicKeyToken=$AssemblyPublicKey"}))
	{
		Log-Event $INFO_EVENT_ID $EVENT_TYPE_INFO ("Loading Assembly $AssemblyName") $TRACE_VERBOSE
		Try {
			[Void][System.Reflection.Assembly]::LoadFrom($DLLPath)
		} Catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Unable to load $DLLPath. $Error") $TRACE_ERROR
			exit 1
		}
	}

	if (!(get-command -Module OMSSearch -Name Get-AADToken -ErrorAction SilentlyContinue)) {
		Log-Event $START_EVENT_ID $EVENT_TYPE_WARNING ("Get-AADToken Commandlet doesn't exist.") $TRACE_WARNING
		Throw-KeepDiscoveryInfo
		exit 1
	}
	$token = Get-AADToken -TenantADName $TenantADName -Username $Username -Password $Password
	if (! $token) {Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Get-AADToken canno authenticate user $username " + $Error) $TRACE_ERROR; exit 1;}
}
catch {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Main " + $Error) $TRACE_ERROR
	exit 1
}

#endregion


try
{
# https://msdn.microsoft.com/en-us/library/azure/mt674551.aspx
	#get a list of runbooks to monitor
	try {
		if (! ([String]::IsNullOrEmpty($RunbookId))) {
			$uri='https://management.azure.com{0}?api-version=2015-01-01-preview' -f $RunbookId
			$runbooks = Invoke-ARMGet -Token $token -Uri $uri
		}
		else {
			$uri='https://management.azure.com{0}/runbooks?api-version=2015-01-01-preview' -f $AccountId
			$runbooks = (Invoke-ARMGet -Token $token -Uri $uri).Value
		}
	}
	catch {
		Throw-StatusBagError
		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ('Error getting runbooks for {0} - {1} - {2}' -f $AcccountId, $RunbookId, $Error[0]) $TRACE_ERROR
		write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
		Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
	}

		if ($RunMode -ieq 'Data') {
			foreach($runbook in $runbooks) {      
				try {
					Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
						-msg ('Processing {0}' `
							-f $runbook.Name) `
						-level $TRACE_VERBOSE   
					$uri='{0}/JobsByRunbook?compositeIdentifier={1}&runbookId={2}&pageLink=&isFirstPage=true' -f $automationURI, $AccountId, $runbook.Name
					$jobs = Invoke-ARMGet -Token $token -Uri $uri
					$lastJobs = @($jobs.Resources | Select-Object -First $lastnJobs)
					$failures = @($lastJobs | where {$_.status -match $FailureCondition}).Count
					$bag = $g_api.CreatePropertyBag()
					$bag.AddValue("QNDType","Data")
					$bag.AddValue('RunbookId', $runbook.Id)
					$lastJobStatus=-1; $lastJobDurationMinutes=-1; $lastJobRuntimeMinutes=-1; $lastJobExecutionTime=-1; $lastJobExecutionAge=-1
					$returnedJobs=-1;$selectedJobs=-1
					$ageError='False'; $runtimeError='False'

				if ($lastJobs.Count -gt 0) {
			
					if ([String]::IsNullOrEmpty($lastJobs[0].EndTime)) {
						$lastJobDurationMinutes= ((Get-Date) - [datetime]($lastJobs[0].createdTime)).TotalMinutes
						$lastJobRuntimeMinutes= ((Get-Date) - [datetime]($lastJobs[0].startTime)).TotalMinutes
						$lastJobExecutionTime = $lastJObs[0].createdTime
						$lastJobExecutionAge = ((Get-Date)- [datetime]($lastJObs[0].createdTime)).TotalHours
					}
					else {
						$lastJobDurationMinutes= ([datetime]($lastJobs[0].EndTime) - [datetime]($lastJobs[0].createdTime)).TotalMinutes
						$lastJobRuntimeMinutes= ([datetime]($lastJobs[0].EndTime) - [datetime]($lastJobs[0].startTime)).TotalMinutes
						$lastJobExecutionTime = $lastJObs[0].endTime
						$lastJobExecutionAge = ((Get-Date)- [datetime]($lastJObs[0].endTime)).TotalHours
					}
					$lastJobStatus = $lastJobs[0].status
					$returnedJobs=$jobs.Resources.Count
					$selectedJobs=$lastjobs.Count

					#return calculated status and input parameters
					$execError=($failures -gt $MaxFailures).ToString()
					if($MaxAge -eq -1) {$ageError='False'} else {$ageError=($lastJobExecutionAge -gt $MaxAge).ToString()}
					if($MaxRuntime -eq -1) {$runtimeError='False'} else {$runtimeError=($lastJobRuntimeMinutes -gt $MaxRuntime).ToString()}

				} 
				#get a list of webhhoks and check if they're about to expire
				$WebHookStatus='OK'
				$daysToExpiration=999
				$WebHookName='none'
				if ($WebHookExpirationDays -ne -1) {
					$uri='{0}/WebhooksForRunbook?compositeIdentifier={1}&runbookName={2}' -f $automationURI, $AccountId, $runbook.Name
					$webhooks = @(Invoke-ARMGet -Token $token -Uri $uri)
					if ($webhooks.count -gt 0) {
						foreach($wh in $webhooks) {
							if ($wh.IsEnabled -ieq 'True') {
								$daysToExpiration = ([datetime]($wh.expirationTime) - (Get-Date)).TotalDays
								if($daysToExpiration -le $WebHookExpirationDays -and $daysToExpiration -gt (-$WebHookExpirationSilence)) {$WebHookStatus='EXPIRE'; $WebHookName=$wh.Name;break;}
							}
						}
					}
				}		

					$bag.AddValue('JobsReturned', $returnedJobs)
					$bag.AddValue('JobsSelected', $selectedJobs)
					$bag.AddValue('Failures', $failures)
					$bag.AddValue('LastJobDurationMinutes', $lastJobDurationMinutes)
					$bag.AddValue('LastJobRuntimeMinutes', $lastJobRuntimeMinutes)
					$bag.AddValue('LastJobStatus', $lastJobStatus)
					$bag.AddValue('LastJobExecutionTime', $lastJobExecutionTime)
					$bag.AddValue('LastJobExecutionAgeHours', $lastJobExecutionAge)

					$bag.AddValue('ExecError', $execError)
					$bag.AddValue('AgeError', $ageError)
					$bag.AddValue('RuntimeError', $runtimeError)

					$bag.AddValue('MaxFailures', $MaxFailures)
					$bag.AddValue('MaxAge', $maxAge)
					$bag.AddValue('MaxRuntime', $maxRuntime)		

					$bag.AddValue('WebHookStatus', $WebHookStatus)
					$bag.AddValue('DaysToExpiration', $daysToExpiration)
					$bag.AddValue('WebHookName', $WebHookName)

					if($traceLevel -eq $TRACE_DEBUG) {$g_API.AddItem($bag)}
					$bag

					Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
						-msg ('{0} - retunred jobs {1} selected jobs {2} failures {3} last job status {4} job duration {5} job run time {6} last Execution {7} age {8}' `
							-f $runbook.Name, $jobs.resources.Count, $lastJobs.Count, $failures, $lastjobStatus, $lastJobDurationMinutes, $lastJobRuntimeMinutes, $lastJobExecutionTime, $lastJobExecutionAge) `
						-level $TRACE_VERBOSE              
					}
				catch {
					Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error getting stats for runbook {0} - {1}' -f $runbook.Name, $Error[0]) $TRACE_WARNING	
					write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
					Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
					continue;
				}
			}
		}
		else {
			$bag = $g_api.CreatePropertyBag()
			$bag.AddValue("QNDType","Status")
			$bag.AddValue("Status","OK")
			$bag.AddValue("Description","Connection OK")
			$bag
		}

		If ($traceLevel -eq $TRACE_DEBUG)
		{
			#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
			#it breaks in exception when run insde OpsMgr and POSH IDE	
			$g_API.ReturnItems() 
		}
		Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Throw-StatusBagError
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
