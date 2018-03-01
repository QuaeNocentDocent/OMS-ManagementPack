

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
[string]$APIVersion='2016-05-01',
[double]$Tolerance=0.5,
[Parameter (Mandatory=$false)] [int]$LookbackDays=8,
[Parameter (Mandatory=$false)] [int]$LastNJobs=5,
[Parameter (Mandatory=$false)] [int]$MaxFailures=0,
[Parameter (Mandatory=$false)] [String]$FailureCondition='Failed',
[Parameter (Mandatory=$false)] [int]$AutoMaxAgeHours=0,
[Parameter (Mandatory=$false)] [int]$FixedMaxAgeHours=24,
[Parameter (Mandatory=$false)] [int]$timeoutSeconds=300,
[Parameter (Mandatory=$false)][int]$Heartbeat=11
)
 
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME	= "Get-OMSRecoveryItemStatus"
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
	Log-Event -eventID $EVENT_ID_START -eventType $EVENT_TYPE_INFORMATION -msg ("Starting script [{0}]. Invocation Name:{1}`n Parameters`n{2}" -f $SCRIPT_NAME, $Invocation.InvocationName, $line) -level $TRACE_INFO
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

Function Get-OMSRecItems
{
param(
	$uris, $connection
)

	$items=@()
	foreach($uri in $uris) {
		$nextLink=$null
		Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_SUCCESS ("Getting items $uri") $TRACE_VERBOSE
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken $connection -nextLink $nextLink -TimeoutSeconds $timeoutSeconds
			$nextLink = $result.NextLink
			if($result.gotValue) {$items+=$result.Values}
		} while ($nextLink)
	}
	return $items
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
	Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ("Cannot logon to AzureAD error: {0} for {2} on Subscription {1}" -f $Error[0], $SubscriptionId, $resourceURI) -level $TRACE_ERROR	
	Throw-KeepDiscoveryInfo
	exit 1	
}
#endregion

try {



	$uris =@(
		('{0}{1}/backupProtectedItems?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
		#('{0}{1}/backupProtectedItems?api-version={2}&$filter=backupManagementType eq ''AzureIaasVM'' and itemType eq ''VM''' -f $ResourceBaseAddress,$resourceURI,$apiVersion),
		#('{0}{1}/backupProtectedItems?api-version={2}&$filter=backupManagementType eq ''MAB'' and itemType eq ''FileFolder''' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
	)
	$items = Get-OMSRecItems -uris $uris -connection $connection

<#

ContainerId: /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/Windows;pre
             -subca.pre.lab
# MAB + FileFolder

id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/Windows;PRE
             -SUBCA.PRE.LAB/protectedItems/FileFolder;C
name       : C
type       : Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems
properties : @{friendlyName=C:\; computerName=PRE-SUBCA.PRE.LAB; protectedItemType=MabFileFolderProtectedItem; backupManagementType=MAB; workloadType=FileFolder; containerName=PRE-SUBCA.PRE.LAB; 
             lastRecoveryPoint=2016-05-12T09:16:43.0837478Z} 
#>

<#

ContainerId: /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/IaasVMConta
             iner;iaasvmcontainer;pre-infrastructure;pre-adsync

AzureIaasVM + VM
id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/IaasVMConta
             iner;iaasvmcontainer;pre-infrastructure;pre-adsync/protectedItems/VM;iaasvmcontainer;pre-infrastructure;pre-adsync
name       : iaasvmcontainer;pre-infrastructure;pre-adsync
type       : Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems
properties : @{friendlyName=pre-adsync; virtualMachineId=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/Pre-Infrastructure/providers/Microsoft.ClassicCompute/virtualMachines/pre-adsync; 
             protectionStatus=Healthy; protectionState=IRPending; lastBackupStatus=; lastBackupTime=2001-01-01T00:00:00Z; protectedItemType=Microsoft.ClassicCompute/virtualMachines; 
             backupManagementType=AzureIaasVM; workloadType=VM; containerName=iaasvmcontainer;pre-infrastructure;pre-adsync; 
             policyId=/Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupPolicies/VMLab1; policyName=VMLab1}
 
#>

	$now = Format-Time -utcTime ((Get-Date).ToUniversalTime())
	$then = Format-Time -utcTime (((Get-Date).ToUniversalTime()).AddDays(-$LookbackDays))
	$uris=@(
		('{0}{1}/backupJobs?api-version={2}&$filter=operation eq ''Backup'' and startTime eq ''{3}'' and endTime eq ''{4}''' -f $ResourceBaseAddress,$resourceURI,$APIVersion, $then, $now)
	)

<#
Job dump
id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupJobs/8c62074b-4657-418f-a0d0-a225666f5015
name       : 8c62074b-4657-418f-a0d0-a225666f5015
type       : Microsoft.RecoveryServices/vaults/backupJobs
properties : @{jobType=AzureIaaSVMJob; duration=02:05:37.9565506; actionsInfo=System.Object[]; virtualMachineVersion=Compute; entityFriendlyName=precentos1; backupManagementType=AzureIaasVM; 
             operation=Backup; status=Completed; startTime=2016-05-08T05:34:50.0304135Z; endTime=2016-05-08T07:40:27.9869641Z; activityId=d48c5135-8309-47db-a277-6fe44ec0bd7a} 
#>


	if($LastNJobs -gt 1) {$jobs = Get-OMSRecItems -uris $uris -connection $connection}

	$uris=@(
		('{0}{1}/backupPolicies?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion)
	)

	if($AutoMaxAgeHours -eq 0) {
		$policySLA=@{}
		$policies = Get-OMSRecItems -uris $uris -connection $connection
		foreach($pol in $policies) {
			switch ($pol.properties.schedulePolicy.scheduleRunFrequency) 
			{
				'Daily' {$slaHours=24*(1+$Tolerance)}
				'Weekly' {$slaHours=(24*7)*(1+$Tolerance)}
				default {
					$slaHours=24*(1+$Tolerance)
					Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Unknown schedule policy {0}' -f $pol.properties.schedulePolicy.scheduleRunFrequency) $TRACE_WARNING	
				}
			}
			$policySLA.Add($pol.name,$slaHours)
		}
	}

<#
Policy Dump
id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupPolicies/DefaultPolicy
name       : DefaultPolicy
type       : Microsoft.RecoveryServices/vaults/backupPolicies
properties : @{backupManagementType=AzureIaasVM; schedulePolicy=; retentionPolicy=; protectedItemsCount=0}
backupManagementType : AzureIaasVM
schedulePolicy       : @{schedulePolicyType=SimpleSchedulePolicy; scheduleRunFrequency=Daily; scheduleRunTimes=System.Object[]}
retentionPolicy      : @{retentionPolicyType=LongTermRetentionPolicy; dailySchedule=}
protectedItemsCount  : 0
schedulePolicyType   : SimpleSchedulePolicy
scheduleRunFrequency : Daily
scheduleRunTimes     : {2016-02-24T16:30:00} 
#>

			foreach($item in $items) {      
			try {
				Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
					-msg ('Processing {0}' `
						-f $item.Name) `
					-level $TRACE_VERBOSE   

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
						$uri=('{0}{1}?api-version={2}' -f $ResourceBaseAddress,$lastJob.Id,$APIVersion)
						$lastJobDetails = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken $connection -nextLink $null -TimeoutSeconds $timeoutSeconds
						if($lastJobDetails.StatusCode -eq 200) { $lastJobDetails=$lastJobDetails.Values[0]}
						else {$lastJobDetails=$null}
					}
				}

				#get last job stats
				$lastjobDurationHours=-1
				$lastJobSizeGB=-1
				$lastJobStatus='n.a.'
				if($lastJobDetails) {
					if ($lastJobDetails.properties) {
						try {
						$lastJobStatus = $lastJobDetails.properties.status
						$lastjobDurationHours = (([datetime]$lastJobDetails.properties.duration).TimeOfDay).TotalHours
						$lastJobSizeGB = ([int]($lastJobDetails.properties.extendedInfo.propertyBag.'Backup Size').Replace(' MB',''))/1024
						}
						catch {
							Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Issue getting last job details for {0} - {1}' -f $item.name, $uri) $TRACE_WARNING	
						}
					}
				}
				#if MaxAAgeHours==0 then let's go dynaminc and try to infer the SLA from the policy
				$ageError='False'
				switch ($item.properties.protectedItemType)
				{
					'Microsoft.Compute/virtualMachines' {$ageMode='Auto'}
					'Microsoft.ClassicCompute/virtualMachines' { $ageMode='Auto'}	
					'MabFileFolderProtectedItem' { $ageMode='Fixed' }
					default { 
						if ([String]::IsNullOrEmpty($item.properties.policyName)) {$ageMode='Fixed'} else {$ageMode='Auto'}
						Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Unrecognized Item Type {0}' -f $item.properties.protectedItemType) $TRACE_WARNING	
					}
				}
					
				if($ageMode -eq 'Auto') {
					$specificAge=$AutoMaxAgeHours
					switch ($AutoMaxAgeHours) {
						0 {
							if ($policySLA.ContainsKey($item.properties.policyName)) {
								$specificAge=$policySLA[$item.properties.policyName]
								$ageError=($lastRecoveryPointAgeHours -gt $specificAge).ToString()
							}
							break;
						}
						-1 {$ageError='False'; break;}
						default {$ageError=($lastRecoveryPointAgeHours -gt $AutoMaxAgeHours).ToString()}
					}
				}
				else {
						switch ($FixedMaxAgeHours) {
						-1 {$ageError='False'; break;}
						default {$ageError=($lastRecoveryPointAgeHours -gt ($FixedMaxAgeHours*(1+$Tolerance))).ToString()}
						}
				}
				$bag = $g_api.CreatePropertyBag()
				$bag.AddValue('ItemId', $item.Id)
				$bad.AddValue('ProtectionStatus', $item.protectionStatus)
				$bad.AddValue('ProtectionState', $item.protectionState)
				$bad.AddValue('HealthStatus', $item.HealthStatus)
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

				Log-Event -eventID $SUCCESS_EVENT_ID -eventType $EVENT_TYPE_INFORMATION `
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
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_INFORMATION ("$SCRIPT_NAME has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
		Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ("Main got error: {0} for {2} on Subscription {1}" -f $Error[0], $SubscriptionId, $resourceURI) -level $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}

