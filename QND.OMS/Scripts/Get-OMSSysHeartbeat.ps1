
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
[int] $MaxAgeMinutes=30,
[int] $LookBackHours=24*7,
[int] $allInstances=0, #issues managing boolean values from OpsMgr
[string] $excludePattern
)
 
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSSysHeartbeat"
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
$EVENT_ID_FAILURE = 4000		#errore generico nello script
$EVENT_ID_SUCCESS = 1101
$EVENT_ID_START = 1102
$EVENT_ID_STOP = 1103

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
    foreach($key in $Invocation.BoundParameters.Keys) {$line += ('-{0} {1} ' -f $key, $Invocation.BoundParameters[$key])}
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
	param($eventID, $eventType, $msg, $level, [switch] $includeName=$true)
	
	Write-Verbose ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
	if($level -le $P_TraceLevel)
	{
		Write-Host ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
		if ($includeName) {$msg='[{0}] {1}' -f $SCRIPT_NAME, $msg}
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
	Log-Event $EVENT_ID_FAILURE $EVENT_TYPE_WARNING "Exiting with empty discovery data" $TRACE_INFO
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
	Log-Event $EVENT_ID_FAILURE $EVENT_TYPE_WARNING "Exiting with null non snapshot discovery data" $TRACE_INFO
	$oDiscoveryData    
	If($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		$g_API.Return($oDiscoveryData)
	}
}

#endregion

#region Property Bags
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
		

		Log-Event -eventID $EVENT_ID_SUCCESS -eventType $EVENT_TYPE_INFORMATION `
			-msg ('{0} - returned status bag ' `
				-f $object[$key]) `
			-level $TRACE_VERBOSE 
    }
    catch {
		Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_WARNING `
			-msg ('{0} - error creating status bag {1}' `
				-f $object[$key]), $_.Message `
			-level $TRACE_VERBOSE 
    }
}
#endregion

#region common utilities
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

#endregion


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
		Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ('Cannot load reuired powershell modules {0}' -f $Error[0]) -level $TRACE_ERROR
		exit 1	
	}

try
{
	if($proxy) {
		Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_WARNING -msg ('CProxy is not currently supported {0}' -f $proxy) -level $TRACE_WARNING
	}
	$pwd = ConvertTo-SecureString $ADPassword -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential ($ADUserName, $pwd)
	$connection = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $cred
}
catch {
	Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ('Cannot get Azure AD connection aborting {0}' -f $Error[0]) -level $TRACE_ERROR
	exit 1	
}

try {
	$timeout=300
#get the orkspaceid useful for link
	$uri = '{0}{1}?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
	[array]$result = (invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection.CreateAuthorizationHeader()) -TimeoutSeconds $timeout).Values
	if ($result.Count -eq 1) {
		$workspaceId=$result[0].properties.customerId
	}
	else {
		Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_WARNING -msg ('Cannot get workspaceid for {0}' -f $uri) -level $TRACE_WARNING
		$workspaceId='error'
	}
	#prepare query body

	#$uri = '{0}{1}/search?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
	$query='Type:Heartbeat | dedup Computer'
	$startDate=(Get-Date).ToUniversalTime().AddHours(-$LookBackHours)
	$endDate=(Get-Date).ToUniversalTime()
	$systems=Get-QNDOMSQueryResult -query $query -startDate $startDate -endDate $endDate -authToken ($connection.CreateAuthorizationHeader()) -ResourceBaseAddress  $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $OMSAPIVersion -timeout $timeout

	#exluded systems
	$cleanSys = @()
	If(! [String]::IsNullOrEmpty($excludePattern)) {
		$systems | %{if($_.Computer -inotmatch $excludePattern){$cleanSys+=$_}}	
	}
    else {
        $cleanSys = $systems
    }

	$link=('https://{0}.portal.mms.microsoft.com/#Workspace/search/index?q=Type%3AHeartbeat%20%7C%20dedup%20Computer' -f $workspaceId)
	write-verbose ('Return systems {0} clean systems {1}' -f $systems.count, $cleanSys.Count)
	if ($allInstances -gt 0) {
		foreach($sys in $cleanSys) {
				$diff = [DateTime]::Now - [DateTime]($sys.TimeGenerated)
				$hash=@{
				'QNDType' ="Data"
				'Computer'= $sys.Computer.ToLower()
				'LastData'= $sys.TimeGenerated	
				'AgeMinutes'= $diff.TotalMinutes
				'Url'=$link
				}	
				Return-Bag -object $hash -key Computer
		}
	}
	else {
		$obsolete = @()
		$cleanSys | %{if(([DateTime]::Now - [DateTime]($_.TimeGenerated)).TotalMinutes -ge $MaxAgeMinutes) {$obsolete+=$_}}
		write-verbose ('Obsolete systems {0}' -f $obsolete.count)
		if($obsolete.count -gt 0) {$sampleSys = ($obsolete | select -first 5 | ConvertTo-Json)}
		else {$sampleSys=''}

		$hash=@{
			'QNDType' ="Summary"
			'ObsoleteDataSystems'= $obsolete.count
			'AgeMinutes'= $maxAgeMinutes
			'First5'= $sampleSys
			'Url'=$link
		}			
		Return-Bag -object $hash -key QNDType
	}

	$heartbeat=11
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

	
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}



