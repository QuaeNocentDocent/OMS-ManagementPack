
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - 
# Author	  -  - Progel spa
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
#				SourceId ($ MPElement $ )
#				ManagedEntityId ($ Target/Id $)
#
# Output properties
#
# Status
#
# Version History
#
# (c) Copyright 2016, Progel spa, All Rights Reserved
# Proprietary and confidential to Progel spa              
#
#*************************************************************************


# Get the named parameters
param(
[Parameter(Mandatory=$true)]
[ValidateScript({$_ -ge 0 -and $_ -le 5})]
[int]$traceLevel,
[Parameter (Mandatory=$true)][string]$clientId,
[Parameter (Mandatory=$true)][string]$SubscriptionId,
[string]$Proxy,
[Parameter (Mandatory=$true)][string]$AuthBaseAddress,
[Parameter (Mandatory=$true)][string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)][string]$ADUserName,
[Parameter (Mandatory=$true)][string]$ADPassword,
[Parameter (Mandatory=$true)][string]$resourceURI,
[Parameter (Mandatory=$true)][string]$apiVersion,
[Parameter (Mandatory=$false)][int]$TimeoutSeconds=300,
[Parameter (Mandatory=$false)][int]$QuotaGB,
[Parameter (Mandatory=$false)][double]$ThresholdP

)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "Get-FileStorageStats.ps1"
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
$EVENT_ID_DETAILS = 1104

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

function lognullasempty
{
 Param($o)
 if(!$o) {return ''''''}
 return $o
}

function Log-Params
{
    param($Invocation)
    $line=''
    foreach($key in $Invocation.BoundParameters.Keys) {$line += ('-{0} {1} ' -f $key, (lognullasempty $Invocation.BoundParameters[$key]))}
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
		if ($includeName) {$msg='[{0}] {1}' -f $SCRIPT_NAME, $msg.toString()}
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
		Log-Event -EventId $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ('Cannot load required powershell modules {0}' -f $Error[0]) -level $TRACE_ERROR
		exit 1	
	}

try
{
	if($proxy) {
		Log-Event -EventId $EVENT_ID_FAILURE -eventType $EVENT_TYPE_WARNING -msg ('Proxy is not currently supported {0}' -f $proxy) -level $TRACE_WARNING
	}
	$pwd = ConvertTo-SecureString $ADPassword -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential ($ADUserName, $pwd)
	$connection = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $cred
}
catch {
	Log-Event -EventId $EVENT_ID_FAILURE -eventType $EVENT_TYPE_WARNING -msg ('Cannot get Azure AD connection aborting {0}' -f $Error[0]) -level $TRACE_WARNING
	Throw-KeepDiscoveryInfo
	exit 1	
}

try
{
#need to manage APIVersion based on type sigh
if($resourceURI -imatch 'Microsoft.ClassicStorage') {$apiVersion='2016-04-01'}

	$uri ='{0}{1}/listKeys?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion
	$sa = ($resourceURI.Split('/'))[($resourceURI.SPlit('/')).Count-1]
	
	Log-Event -EventId $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFO -msg ('About the ask for keys for {0}' -f $sa) -level $TRACE_VERBOSE
	$keys = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken ($connection.CreateAuthorizationHeader()) -nextLink $null -TimeoutSeconds $timeoutSeconds
	if ($keys.Values) {
        if($keys.Values.primaryKey) {$saKey=$keys.Values.primaryKey}
        else {$sakey=$keys.Values.Keys[0].Value}
	}
	else {
		throw ('Cannot get storage account key {0}' -f $sa)
	}

    	Log-Event -EventId $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFO -msg ('About to query for shares for {0}' -f $sa) -level $TRACE_VERBOSE
    $uriListShares = 'https://{0}.file.core.windows.net/?comp=list' -f $sa
    $result = Invoke-QNDAzureStorageRequest -uri $uriListShares -verb GET -key $sakey -version '2015-02-21' -searchTag 'Share' -TimeoutSeconds $TimeoutSeconds
    if($result.ParsedValues) {
        foreach($share in $result.ParsedValues) {
			try {
				#discover FileShare			
				Log-Event -EventId $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFO -msg ('Processing share {0} in {1}' -f $share.name, $sa) -level $TRACE_VERBOSE
				#write-host ('{0} quota {1}GB' -f $share.name, $share.properties.Quota)
				$uri='https://{0}.file.core.windows.net/{1}?restype=share&comp=stats' -f $sa, $share.Name
				$stats = Invoke-QNDAzureStorageRequest -uri $uri -verb GET -key $saKey -version '2015-02-21' -searchTag 'ShareUsage' -rootTag 'ShareStats' -TimeoutSeconds $TimeoutSeconds
				$currentUsageGB=[int]$stats.ParsedValues[0].'#text'
				if( ($currentUsageGB / $QuotaGB * 100) -gt $ThresholdP) {$status='Over'} else {$Status='Under'}
				$hash=@{
					'ShareName'=$share.Name
					'CurrentUsageGB'=$currentUsageGB
					'CurrentUsagePer'=($currentUsageGB / $QuotaGB * 100)
					'ThresholdP'=$ThresholdP
					'Status'=$Status
				}
				Return-Bag -object $hash -key 'ShareName'
			}
			catch {
				Log-Event -eventID $EVENT_ID_ERROR -eventType $EVENT_TYPE_WARNING -msg ('Error processing stats for {0} in account {1}' -f $share.name, $sa) -level $TRACE_WARNING
			}
        }
    }
    
	if($traceLevel -eq $TRACE_DEBUG) {
		write-warning 'Exception expected if run inside powershell ISE'
		$g_API.ReturnItems()
	}

	Log-Event -eventID $EVENT_ID_STOP -eventType $EVENT_TYPE_INFORMATION -msg ('{0} has completed successfully in {1} seconds.' -f $SCRIPT_NAME, ((Get-Date)- ($dtstart)).TotalSeconds) -level $TRACE_INFO
}
Catch [Exception] {
	Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ("Main got error: {0} " -f $Error[0]) -level $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
