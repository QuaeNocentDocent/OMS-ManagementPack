

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/

#*************************************************************************
# Script Name - Get-OMSBackupStatus
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
	[Parameter (Mandatory=$True)] [String]$VaultId,
	[Parameter (Mandatory=$true)] [String]$Username,
	[Parameter (Mandatory=$true)] [String]$Password,
	[Parameter (Mandatory=$false)] [String]$Proxyurl, #nyi
	[Parameter (Mandatory=$false)] [int]$LookbackDays=8,
	[Parameter (Mandatory=$false)] [int]$LastNJobs=5,
	[Parameter (Mandatory=$false)] [int]$MaxFailures=0,
	[Parameter (Mandatory=$false)] [String]$FailureCondition='Failed',
	[Parameter (Mandatory=$false)] [int]$MaxAgeHours=-1,
	[Parameter (Mandatory=$false)] [String]$ItemId,
	[Parameter (Mandatory=$false)] [String]$RunMode='Data'
)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSBackupStatus"
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

Function Format-Time
{
	[OutputType([String])]
	param($utcTime)


	$fTime=$utcTime.ToString('yyyy-MM-dd hh:mm:ss tt')
	#don't know why tt doens't work
	#quick fix without reverting to -net framework formatting
	if($fTime.IndexOf('M') -eq -1) {
		if ($fTime.Hour -lt 13) {$fTime+= 'AM'} else {$fTime += 'PM'}
	}
	return $fTime
}

Function Get-BackupJob
{
param($token, $vaultId, $lookbackDays)
		try {
			$now = Format-Time -utcTime ((Get-Date).ToUniversalTime())
			$then = Format-Time -utcTime (((Get-Date).ToUniversalTime()).AddDays(-$LookbackDays))
			$uri='https://management.azure.com{0}/jobs?api-version=2014-09-01&$filter=operation eq ''Backup'' and startTime eq ''{1}'' and endTime eq ''{2}''' -f $VaultId, $then, $now
			$jobs = @((Invoke-ARMGet -Token $token -Uri $uri).Value)
			Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
				-msg ('Got {0} jobs' `
					-f $jobs.Count) `
				-level $TRACE_VERBOSE 
		}
		catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ('Error getting backup jobs for {0} - {1}' -f $VaultId, $Error[0]) $TRACE_ERROR
			write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
			Write-Verbose $("TRAPPED: " + $_.Exception.Message);
		}
		return $jobs
}

Function Get-VaultPolicy
{
param($token, $vaultId)
		try {
			$uri='https://management.azure.com{0}/protectionPolicies?api-version=2014-09-01' -f $vaultId
			$jres = Invoke-ARMGet -Token $token -Uri $uri
			$policies=@{}
			foreach($pol in $jres.value) {
				switch ($pol.properties.backupSchedule.scheduleRun) 
				{
					'Daily' {$slaHours=28}
					'Weekly' {$slaHours=24*7+12}
					default {$slaHours=28}
				}
				$policies.Add($pol.name,$slaHours)
			}
			Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
				-msg ('Got {0} policies' `
					-f $jres.value.Count) `
				-level $TRACE_VERBOSE 
		}
		catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ('Error getting backup policies for {0} - {1}' -f $VaultId, $Error[0]) $TRACE_ERROR
			write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
			Write-Verbose $("TRAPPED: " + $_.Exception.Message);
		}
		return $policies
}

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

	#get a list of items to monitor
	try {
		if (! ([String]::IsNullOrEmpty($ItemId))) {
		#nyi
			throw 'Single Item check Not Yet Implemented'
		}
		else {
			$uri='https://management.azure.com{0}/protectedItems?api-version=2014-09-01' -f $VaultId			
			$items = (Invoke-ARMGet -Token $token -Uri $uri).Value
		}
	}
	catch {
		Throw-StatusBagError
		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ('Error getting backup items for {0} - {1} - {2}' -f $VaultId, $ItemId, $Error[0]) $TRACE_ERROR
		write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
		Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
	}

	if ($RunMode -ieq 'Data') {
		#get the backup jobs
		#this can become huge but right now I didn't find a way to filter for the specific protected Item
		$jobs=$null
		$policies=@{}
		if($LastNJobs -gt 1) {$jobs = Get-BackupJob -token $token -vaultId $VaultId -lookbackDays $LookbackDays}
		if($MaxAgeHours -eq 0) {$policies = Get-VaultPolicy -token $token -vaultId $VaultId}

		foreach($item in $items) {      
			try {
				Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
					-msg ('Processing {0}' `
						-f $item.Name) `
					-level $TRACE_VERBOSE   
				#getting recovery points
				#$itemId= ($item.id).Replace('items','protectedItems')
				#$uri='https://management.azure.com{0}/recoveryPoints?api-version=2014-09-01' -f $itemId
				#$recPoints = Invoke-ARMGet -Token $token -Uri $uri
				#$lastRecPointDate='01-01-2000'
				#if($recPoints.Value.Count -gt 0) {
				#	$lastRecoveryPoint = ($recPoints.Value | sort @{expression={[datetime]$_.properties.recoveryPointTime};Descending=$true}) | Select-Object -First 1
				#	$lastRecPointDate = $lastRecoveryPoint.properties.recoveryPointTime
				#}
				$lastRecPointDate='2015-01-01'
				if($item.properties.lastRecoveryPoint) {$lastRecPointDate = $item.properties.lastRecoveryPoint}
				$lastRecoveryPointAgeHours = ((Get-Date) - [datetime]$lastRecPointDate).TotalHours

				#getting jobs
				if ($LastNJobs -gt 1) {
					$itemJobs=@($jobs | where {$_.properties.entityFriendlyName -ieq $item.properties.friendlyName})
					$lastJob = $itemjobs | where {$_.properties.status -ieq 'Completed'} | Select-Object -First 1
					$selectedJobs = @($itemJobs | Select-Object -First $LastNJobs)
					$failures = @($selectedJobs | where {$_.properties.status -match $FailureCondition}).Count
					if ($lastJob) {
						$uri='https://management.azure.com{0}?api-version=2014-09-01' -f $lastJob.id
						$lastJobDetails = Invoke-ARMGet -Token $token -Uri $uri
					}
				}
				else {
					$uri='https://management.azure.com{0}/jobs/{1}?api-version=2014-09-01' -f $vaultId, $item.properties.lastBackupJobId
					$lastJobDetails = Invoke-ARMGet -Token $token -Uri $uri
				}
				#get last job stats
				$lastjobDurationHours=-1
				$lastJobSizeGB=-1
				$lastJobStatus='n.a.'
				if($lastJobDetails) {
					if ($lastJobDetails.properties) {
						$lastJobStatus = $lastJobDetails.properties.Status
						$lastjobDurationHours = (([datetime]$lastJobDetails.properties.duration).TimeOfDay).TotalHours
						$lastJobSizeGB = ([int]($lastJobDetails.properties.propertyBag.'Backup Size').Replace(' MB',''))/1024
					}
				}
				#if MaxAAgeHours==0 then let's go dynaminc and try to infer the SLA from the policy
				$ageError='False'
				$specificAge=$MaxAgeHours
				switch ($MaxAgeHours) {
					0 {
						$item.properties.containerId -match '(^.*protectedItems\/)' | Out-Null
						$policyName=$item.properties.protectionPolicyId.Replace($matches[0],'')
						if ($policies.ContainsKey($policyName)) {
							$specificAge=$policies[$policyName]							
							$ageError=($lastRecoveryPointAgeHours -gt $specificAge).ToString()
						}
						break;
					}
					-1 {$ageError='False'; break;}
					default {$ageError=($lastRecoveryPointAgeHours -gt $MaxAgeHours).ToString()}
				}

				$bag = $g_api.CreatePropertyBag()
				$bag.AddValue("QNDType","Data")
				$bag.AddValue('ItemId', $item.Id)


				#return calculated status and input parameters
				$execError=($failures -gt $MaxFailures).ToString()

				$bag.AddValue('JobsReturned', $itemJobs.Count)
				$bag.AddValue('JobsSelected', $selectedJobs.Count)
				$bag.AddValue('Failures', $failures)
				$bag.AddValue('LastJobDurationHours', $lastjobDurationHours)
				$bag.AddValue('LastJobSizeGB', $lastJobSizeGB)
				$bag.AddValue('LastJobStatus', $lastJobStatus)
				$bag.AddValue('LastRecoveryPointDate', $lastRecPointDate)
				$bag.AddValue('LastRecoveryPointAge', $lastRecoveryPointAgeHours)

				$bag.AddValue('ExecError', $execError)
				$bag.AddValue('AgeError', $ageError)

				$bag.AddValue('MaxFailures', $MaxFailures)
				$bag.AddValue('MaxAgeHours', $specificAge)


				if($traceLevel -eq $TRACE_DEBUG) {$g_API.AddItem($bag)}
				$bag

				Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
					-msg ('{0} - retunred jobs {1} selected jobs {2} failures {3} last job status {4} last job duration {5} last recovery point {6} last recovery point age {7}' `
						-f $item.Id, $itemJobs.Count, $selectedJobs.Count, $failures, $lastJobStatus, $lastjobDurationHours, $lastRecPointDate, $lastRecoveryPointAgeHours) `
					-level $TRACE_VERBOSE              
				}
			catch {
				Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error getting stats for item {0} - {1}' -f $Item.Name, $Error[0]) $TRACE_WARNING	
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
