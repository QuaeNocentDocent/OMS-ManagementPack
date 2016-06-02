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
[Parameter (Mandatory=$true)] [string]$sourceID,
[Parameter (Mandatory=$true)] [string]$ManagedEntityId,
[Parameter (Mandatory=$true)][string]$clientId,
[Parameter (Mandatory=$true)][string]$SubscriptionId,
[Parameter (Mandatory=$true)][string]$ResourceGroupId,
[string]$Proxy,
[Parameter (Mandatory=$true)][string]$AuthBaseAddress,
[Parameter (Mandatory=$true)][string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)][string]$ADUserName,
[Parameter (Mandatory=$true)][string]$ADPassword,
[Parameter (Mandatory=$true)][string]$resourceURI,
[Parameter (Mandatory=$true)][string]$apiVersion
)
 
	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSRecoveryContainer"
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


# File system
<#

id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/Windows;pre
             -subca.pre.lab
name       : Windows;pre-subca.pre.lab
type       : Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers
properties : @{canReRegister=True; containerId=493672; friendlyName=PRE-SUBCA.PRE.LAB; backupManagementType=MAB; registrationStatus=Registered; healthStatus=; containerType=Windows; 
             protectableObjectType=MABWindowsContainer} 
#>

# IaasVM
<#
id         : /Subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/LabReggioInfra/providers/Microsoft.RecoveryServices/vaults/backupARMLabRE/backupFabrics/Azure/protectionContainers/IaasVMConta
             iner;iaasvmcontainer;pre-infrastructure;pre-adsync
name       : IaasVMContainer;iaasvmcontainer;pre-infrastructure;pre-adsync
type       : Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers
properties : @{virtualMachineId=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/Pre-Infrastructure/providers/Microsoft.ClassicCompute/virtualMachines/pre-adsync; 
             virtualMachineVersion=ClassicCompute; resourceGroup=Pre-Infrastructure; friendlyName=pre-adsync; backupManagementType=AzureIaasVM; registrationStatus=Registered; healthStatus=Healthy; 
             containerType=Microsoft.ClassicCompute/virtualMachines; protectableObjectType=Microsoft.ClassicCompute/virtualMachines} 
#>

# DPM Sources
#uniqueName    : fsrveuazbck01.furla.dom
#containerType : Machine
#properties    : @{containerId=482742; friendlyName=FSRVEUAZBCK01.FURLA.DOM; containerStampId=3f2a1395-55ed-4e55-8f40-de1f8a6c2a24; containerStampUri=https://pod01-prot1b.we.backup.windowsazure.com; 
#                canReRegister=False; customerType=DPMVenus}

Function Discover-BackupContainer
{
	param($obj)

	#$obj
	if($obj) {
		try {
			$containerType = '{0}-{1}' -f ($obj.name.Split(';'))[0], $obj.properties.backupManagementType
			$id=$obj.id
			$name=$obj.Name
			$displayName = $obj.properties.friendlyName

			$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Recovery.Vault.Container']$")	
			$objInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.Subscription']/SubscriptionId$", $SubscriptionId)
			$objInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.ResourceGroup']/ResourceGroupId$", $ResourceGroupId)
			$objInstance.AddProperty("$MPElement[Name='Azure!Microsoft.SystemCenter.MicrosoftAzure.AzureServiceGeneric']/ServiceId$", $resourceURI)	

			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Recovery.Vault.Container']/Id$", $id)		
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Recovery.Vault.Container']/Name$", $name)		
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Recovery.Vault.Container']/ContainerType$", $containerType)	
			$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $displayName)	
			$discoveryData.AddInstance($objInstance)	
		}
		catch {
			Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocvering backup container {1} in vault {0} - {2}' -f $name, $Id, $Error[0]) $TRACE_WARNING	
			write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
			Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
		}
	}
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
	$connection = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $cred
}
catch {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Cannot get Azure AD connection aborting $Error") $TRACE_ERROR
	Throw-KeepDiscoveryInfo
	exit 1	
}

try {
	$timeoutSeconds=300
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)

	$uris =@(
		('{0}{1}/backupProtectionContainers?api-version={2}&$filter=backupManagementType eq ''AzureIaasVM''' -f $ResourceBaseAddress,$resourceURI,$apiVersion),
		('{0}{1}/backupProtectionContainers?api-version={2}&$filter=backupManagementType eq ''MAB''' -f $ResourceBaseAddress,$resourceURI,$apiVersion)		
	)	

	foreach($uri in $uris) {
		Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_SUCCESS ("Getting $uri") $TRACE_VERBOSE
		$nextLink=$null
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection.CreateAuthorizationHeader()) -nextLink $nextLink -TimeoutSeconds $timeoutSeconds
			$nextLink = $result.NextLink
			if($result.gotValue) {	
				foreach($container in $result.Values) {
					write-verbose $container.properties.friendlyName
					Discover-BackupContainer $container
				}
			}
		} while ($nextLink)
	}

	$discoveryData
	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		#it breaks in exception when run insde OpsMgr and POSH IDE	
		$g_API.Return($discoveryData)
	}
	
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}




