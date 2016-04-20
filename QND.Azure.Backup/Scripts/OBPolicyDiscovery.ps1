
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
[string]$computerName=$(throw 'must have a value'),
[string]$sourceID=$(throw 'must have a value'),
[string]$ManagedEntityId=$(throw 'must have a value'))

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Progel.Azure.Backup.GetPolicies"
$SCRIPT_ARGS = 4

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



#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date
#if we use named parameters then $Args is always 0, so the erroc hecking must be done differently

#v2
#if ($PsBoundParameters.Count -ne $SCRIPT_ARGS)
#at the momento we must do specific command line validation or use the syntax
#Param([string]$a=$(throw 'My exception - parameter a needed')
#	If ($Args.Count -ne $SCRIPT_ARGS)
#	{
#		Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR "called without proper arguments and was not executed."  $TRACE_ERROR
#		exit -1
#	}

	$P_TraceLevel = $traceLevel
#same story for dumping the command line	
#manul stuff today in v2 we could use $PSBoundParameters
	Log-Params ([string]$traceLevel + " " + $computerName + " " + $sourceID + " " + $ManagedEntityId)
try
{
    if (! (Get-Module -Name MSOnlineBackup)) {Import-Module MSOnlineBackup}
    $policies = Get-OBPolicy | Where {$_.State -eq 'Existing'}
    if ($policies)
    {
        $discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
        foreach ($pol in $policies)
        {
			$PInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Backup.Agent.Policy']$")
			$PInstance.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $computerName)
			$PInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "OB Policy ($($pol.PolicyName))")
			$PInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Agent.Policy']/PolicyName$", $pol.PolicyName)
			$PInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Agent.Policy']/RetentionDays$", $pol.RetentionPolicy.RetentionDays)
			$discoveryData.AddInstance($PInstance)
        }
        $discoveryData
    }
    else
    {
        Throw-EmptyDiscovery $sourceID $ManagedEntityId
    }

	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent		
		$g_API.Return($discoveryData)
	}
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
