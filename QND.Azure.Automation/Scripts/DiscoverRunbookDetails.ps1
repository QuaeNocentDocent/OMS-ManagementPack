
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
[Parameter (Mandatory=$true)] [string]$sourceID,
[Parameter (Mandatory=$true)] [string]$ManagedEntityId,
[Parameter (Mandatory=$true)] [string]$clientId,
[Parameter (Mandatory=$true)] [string]$SubscriptionId,
[Parameter (Mandatory=$true)] [string]$ResourceGroupId,
[string]$Proxy,
[Parameter (Mandatory=$true)] [string]$AuthBaseAddress,
[Parameter (Mandatory=$true)] [string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)] [string]$ADUserName,
[Parameter (Mandatory=$true)] [string]$ADPassword,
[Parameter (Mandatory=$true)] [string]$resourceURI,
[Parameter (Mandatory=$true)] [string]$APIVersion='2015-10-31',
[Parameter (Mandatory=$true)] [int]$APITimeoutSeconds=30)
	
[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "QND.DiscoverRunbookDetails"
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
		

		$bag=''
		$object.Keys | %{$bag+=('{0}={1}///' -f $_,$object[$_])}
		Log-Event -eventID $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFORMATION `
			-msg ('Returned status bag: {0} ' `
				-f $bag) `
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

Function Get-AutomationItems
{
param(
	$uris, $connection
)

	$items=@()
	foreach($uri in $uris) {
		$nextLink=$null
		Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_SUCCESS ("Getting items $uri") $TRACE_VERBOSE
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken $connection -nextLink $nextLink -TimeoutSeconds $APItimeoutSeconds
			$nextLink = $result.NextLink
			if($result.gotValue) {$items+=$result.Values}
            #hacking some unwanted chars
            if($nextLink) {$nextLink=$nextLink.Replace('+','%2B')}
		} while ($nextLink)
	}
	return $items
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

try
{
	$uris =@(('{0}{1}/runbooks?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$apiVersion))
	$runBooks = Get-AutomationItems -uris $uris -connection $connection
	if ($runBooks) {
		Log-Event -eventID $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFORMATION -msg ("Got {0} rubooks" -f $runbooks.Count) -level $TRACE_VERBOSE	
	}
<#
{"id":"/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks/ASR-HybridAutomation//A
SR-HybridAutomation","name":"ASR-HybridAutomation","type":"Microsoft.Automation/AutomationAccounts/Runbooks","location":"West Europe","tags":{"Owner":"Daniele Grandini"},"etag":"\"636123691040030000\"","properties":{"description":"Testing Description
s","logVerbose":false,"logProgress":false,"logActivityTrace":9,"runbookType":"Script","parameters":{},"state":"Edit","jobCount":0,"provisioningState":"Succeeded","serviceManagementTags":null,"outputTypes":[],"creationTime":"2015-09-30T14:16:40.933+00
:00","lastModifiedBy":"live.com#daniele.grandini@live.it","lastModifiedTime":"2016-10-18T06:31:44.003+00:00"}}
#>
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
	foreach($rb in $runbooks) {
		try {
			$detail = invoke-QNDAzureRestRequest -uri ('{0}{1}?api-version={2}' -f $ResourceBaseAddress, $rb.id, $apiVersion) -httpVerb GET -authToken $connection -TimeoutSeconds $APITimeoutSeconds
			if($detail.Values -and $detail.Values.count -eq 1) {
				Log-Event -eventID $EVENT_ID_DETAILS -eventType $EVENT_TYPE_INFORMATION -msg ("Discovering: {0} " -f $rb.Id) -level $TRACE_VERBOSE
				$RBInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Automation.RunbookGen']$")

				#first add the hosting class
				$RBInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.Subscription']/SubscriptionId$", $SubscriptionId)
				$RBInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.ResourceGroup']/ResourceGroupId$", $ResourceGroupId)
				$RBInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.AzureServiceGeneric']/ServiceId$", $resourceURI)	
				#let's add the keys
				$RBInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.ServiceResource']/ResourceId$", $rb.id)
				#param validation
				$tags='n.a.';$description='n.a.'
				$rbdetail=$detail.values[0]
				if($rbdetail.tags) {$tags=([string]$rbdetail.tags)}
				if($rbdetail.properties.description) {$description=([string]$rbdetail.properties.description)}
				if($tags.Length -gt 8190) {$tags=$tags.SubString(0,8190)}
				if($description.Lenght -gt 255) {$description=$description.SubString(0,255)}
				$RBInstance.AddProperty("$MPElement[Name='QNDA!QND.OMS.GenericResource']/Tags$", $tags)
				$RBInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.RunbookGen']/Description$", $description)
				$RBInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.RunbookGen']/RunbookType$", [string]$rbdetail.properties.runbookType)
				$discoveryData.AddInstance($RBInstance)

			}
			else {
				Log-Event -eventID $EVENT_ID_DETAILS -eventType $EVENT_TYPE_WARNING -msg ("Error getting details for: {0} " -f $rb.Id) -level $TRACE_WARNING	
			}
		}
		catch {
			Log-Event -eventID $FAILURE_EVENT_ID -eventType $EVENT_TYPE_WARNING -msg ('Error discovering runbook details {0} - {1}' -f $rb.id, $Error[0]) $TRACE_WARNING	
			write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
			Write-Verbose $("TRAPPED: " + $_.Exception.Message);
		}
	}
	If ($traceLevel -eq $TRACE_DEBUG)
	{
	write-warning 'Exception expected if run inside powershell ISE'
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent		
		$g_API.Return($discoveryData)
	}

	Log-Event -eventID $EVENT_ID_STOP -eventType $EVENT_TYPE_INFORMATION -msg ('{0} has completed successfully in {1} seconds.' -f $SCRIPT_NAME, ((Get-Date)- ($dtstart)).TotalSeconds) -level $TRACE_INFO
}
Catch [Exception] {
	Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ("Main got error: {0} for {2} on Subscription {1}" -f $Error[0], $SubscriptionId, $resourceURI) -level $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
