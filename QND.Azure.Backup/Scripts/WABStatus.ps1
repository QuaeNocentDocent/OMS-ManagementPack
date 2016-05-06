
#Template Notes
#basic error handling with -ErrorVariable -ErrorAction
#EV is myErr set to null/cleared before any critical code section and tested for Count -eq 0 after, if different we have an error
#plain and simple waiting for try/ctach in powershell 2.0
#then every sensitive function should have a trap statement see http://huddledmasses.org/trap-exception-in-powershell/

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - 
# Author	  -  - Progel srl
# Version	  - 1.1 24.09.2007
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
#				SourceId ($MPElement$ )
#				ManagedEntityId ($Target/Id$)
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
param([int]$traceLevel=$(throw 'must have a value'),
[int]$thresholdHours=$(throw 'must have a value'),
[string]$ThresholdSizeGB=$(throw 'must have a value'))

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Progel.Azure.Backup.GetRecovery"
$SCRIPT_ARGS = 3

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

#TypedPropertyBag
$AlertDataType = 0
$EventDataType	= 2
$PerformanceDataType = 2
$StateDataType       = 3

function Log-Params
{
	param([string] $CmdLine)	
	trap { continue; }
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFORMATION  ("Starting script. " + $CmdLine) $TRACE_INFO
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

#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date

	$P_TraceLevel = $traceLevel
#same story for dumping the command line	
#manul stuff today in v2 we could use $PSBoundParameters
	Log-Params ([string]$traceLevel + " " + $computerName + " " + $sourceID + " " + $ManagedEntityId)
try
{
#now it seems we're having issue with this module inside OpsMgr let's try to isolate and ignore it
	try {
		if (! (Get-Module -Name MSOnlineBackup)) {Import-Module MSOnlineBackup}
	}
	catch {
		$message = ("Import-Module MSOnlineBackup: {0}`n{1}`n{2}`nTrying to continue anyway" -f $Error, $_.Exception.GetType().FullName, $_.Exception.Message)
		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING $message $TRACE_WARNING	
		write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
		Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
	}
    $lastRec = Get-OBAllRecoveryPoints | Sort-Object BackupTime -Descending | Select-Object -First 1
    $machineUSage = Get-OBMachineUsage
	$policies = Get-OBPolicy | Where {$_.State -eq 'Existing'}
    $elapsed = ([DateTime]::Now - $lastRec.BackupTime).TotalHours
    Write-Verbose $elapsed
    if ($elapsed -le $thresholdHours)
    {
        $backupStatus = 'UpToDate'
    }
    else
    {
        $backupStatus = 'TooOld'
    }
    if (($machineUsage.StorageUsedByMachineInBytes / 1GB) -ge $ThresholdSizeGB)
    {
        $sizeStatus = 'TooBig'
    }
    else
    {
        $sizeStatus = 'OK'
    }
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	$message = ("Main: {0}`n{1}`n{2}" -f $Error, $_.Exception.GetType().FullName, $_.Exception.Message)
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING $message $TRACE_WARNING	

	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
    $sizeStatus = 'Fail';
    $backupStatus = 'Fail';
}
finally
{
# in the current WAB version we have just one policy per agent, let's build something that can accomodate more policies and keep cook down'
	if ($policies)
	{
		 foreach ($pol in $policies)
		 {
			$bag = $g_API.CreateTypedPropertyBag($StateDataType)
			$bag.AddValue('PolicyName', $pol.PolicyName)

			$bag.AddValue('LastBackupTime', $lastRec.BackupTime)
			$bag.AddValue('BackupAgeHours', $elapsed)

			$bag.AddValue('BackupStatus', $backupStatus)
			$bag.AddValue('MachineUsageGB', $machineUSage.StorageUsedByMachineInBytes/1GB)
			$bag.AddValue('SizeStatus', $sizeStatus)				
			$bag	#this is the way to return data to OpsMgr
			If ($P_TraceLevel -eq $TRACE_DEBUG)
			{
				$message = "BackupTime: $($lastRec.BackupTime)`nBackupStatus: $($backupStatus)`nBackup Age hours: $elapsed`nMachine USage MB: $($machineUSage.StorageUsedByMachineInBytes/(1024*1024))`nSize Status: $sizeStatus" 
				Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_INFORMATION $message $TRACE_DEBUG
			}
		}
	}
}