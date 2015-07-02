

## This discovery needs to be splitted 'cause potentially can discover a huge number of entities
## Gorup memeberhsip must be changed and split in diffrent rules using the properties we're setting

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/

#*************************************************************************
# Script Name - Get-OMSManagedSystems
# Author	  -  - Progel spa
# Version  - 1.0 24.09.2007
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
#	  1.0 06.08.2010 DG First Release
#     1.5 15.02.2014 DG minor cosmetics
#
# (c) Copyright 2015, Progel spa, All Rights Reserved
# Proprietary and confidential to Progel srl              
#
#*************************************************************************


# Get the named parameters
param(
[Parameter (Mandatory=$True)] [int]$traceLevel,
[Parameter (Mandatory=$true)] [string]$sourceID,
[Parameter (Mandatory=$true)] [string]$ManagedEntityId,
[Parameter (Mandatory=$true)] [String]$TenantADName,
[Parameter (Mandatory=$false)] [String]$Subscription,
[Parameter (Mandatory=$false)] [String]$Workspace,
[Parameter (Mandatory=$false)] [String]$ResourceGroup,
[Parameter (Mandatory=$true)] [String]$Username,
[Parameter (Mandatory=$true)] [String]$Password,
[Parameter (Mandatory=$true)] [Int]$ValidHours,
[Parameter (Mandatory=$true)]  [ValidateSet("Subscription", "Workspace", "System",ignorecase=$true)]
[string]$discoveryType,
[String]$Proxyurl #nyi

)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Get-OMSManagedSystems"
$SCRIPT_ARGS = 11
$SCRIPT_STARTED			= 831
$PROPERTYBAG_CREATED	= 832
$SCRIPT_ENDED			= 835
$SCRIPT_VERSION = "1.0"

#region Constants
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


#id                   : /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414
#subscriptionId       : ec2b2ab8-ba74-41a0-bf54-39cc0716f414
#displayName          : Laboratorio Reggio Emilia
#state                : Enabled
#subscriptionPolicies : @{locationPlacementId=Public_2014-09-01; quotaId=EnterpriseAgreement_2014-09-01}

#id       : /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OI-Default-East-US/providers/Microsoft.OperationalInsights/workspaces/99c95eb8-5ef1-4620-9684-74591f39b666
#name     : 99c95eb8-5ef1-4620-9684-74591f39b666
#type     : Microsoft.OperationalInsights/workspaces
#location : eastus

Function Discover-Subscription
{
	param($sub)
		$subInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Azure.Subscription']$")		
		$subInstance.AddProperty("$MPElement[Name='QND.OMS.Azure.Subscription']/Id$", $sub.subscriptionId)		
		$subInstance.AddProperty("$MPElement[Name='QND.OMS.Azure.Subscription']/Name$", $sub.displayName)	
		$subInstance.AddProperty("$MPElement[Name='QND.OMS.Azure.Subscription']/Tenant$", $TenantADName)	
		$subInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $sub.displayName)	
		$discoveryData.AddInstance($subInstance)	
		#$currentTenant = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.AAD.Tenant']$")		
		#$currentTenant.AddProperty("$MPElement[Name='QND.OMS.AAD.Tenant']/Domain$", $TenantADName)		
		#$discoveryData.AddInstance($currentTenant)
		#$rel = $discoveryData.CreateRelationshipInstance("$MPElement[Name='QND.OMS.TenantContainsSubscription']$")
		#$rel.Source=$currentTenant
		#$rel.Target=$subInstance
		#$discoveryData.AddInstance($rel)

}

Function Discover-Workspace
{
	param($obj)
		$obj.Id -match '(?<=(resourceGroups\/))(?<Group>.*)(?=(\/providers))'
		$group = $matches.Group

		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Workspace']$")	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Azure.Subscription']/Id$", $subscription)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Workspace']/Id$", $obj.Name)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Workspace']/Name$", $obj.Name)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Workspace']/ResourceGroup$", $Group)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Workspace']/Subscription$", $Subscription)	
		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.Name)	
		$discoveryData.AddInstance($objInstance)	


}

Function Discover-System
{
	param($obj)

	if ([String]::IsNullOrEmpty($obj.Computer)) {return;}
		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.ManagedSystem']$")	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Azure.Subscription']/Id$", $subscription)
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Workspace']/Id$", $workspace)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.ManagedSystem']/Computer$", $obj.Computer)	
		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.Computer)	
		$discoveryData.AddInstance($objInstance)	


}

#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date
	$P_TraceLevel = $traceLevel
	Log-Params $MyInvocation


try {
	$ResPath = (get-itemproperty -path 'HKLM:\system\currentcontrolset\services\healthservice\Parameters' -Name 'State Directory').'State Directory' + '\Resources'
	if(Test-Path $ResPath) {
		$module = @(get-childitem -path $ResPath -Name OMSSearch.psm1 -Recurse)[0]
	}
	if($module) { $OMSSearchModule = "$ResPath\$module"}
	else {$OMSSearchModule = '.\OMSSearch.psm1'}

	If (Test-Path $OMSSearchModule) {Import-Module $OMSSearchModule}
	else {Throw [System.DllNotFoundException] 'OMSSearch.psm1 not found'}

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

try
{

#ObjectName!="Advisor Metrics" ObjectName!=ManagedSpace | measure max(TimeGenerated) as lastdata by Computer | where lastdata > NOW-240HOURS
#ObjectName!="Advisor Metrics" ObjectName!=ManagedSpace | where TimeGenerated > NOW-240HOURS | measure count() by Computer
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
	switch ($discoveryType) {
		'Subscription' {
			$uri="https://management.azure.com/subscriptions?api-version=2015-01-01"
			$jres = Invoke-ARMGet -Token $token -Uri $uri
			if(! $jres) {Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Invoke-ARMGet failed $uri " + $Error) $TRACE_ERROR; exit 1;}
			foreach($sub in $jres.Value) {Discover-Subscription $sub}
		}
		'Workspace' {
			if([String]::IsNullOrEmpty($subscription)) {Throw-EmptyDiscovery; Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("MIssing SubscriptionId") $TRACE_ERROR	}
			$uri='https://management.azure.com/subscriptions/{0}/resources?$filter=resourceType eq ''Microsoft.OperationalInsights/workspaces''&api-version=2015-01-01' -f $subscription
			$jres = Invoke-ARMGet -Token $token -Uri $uri
			if(! $jres) {Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Invoke-ARMGet failed $uri " + $Error) $TRACE_ERROR; exit 1;}
			foreach($ws in $jres.Value) {Discover-Workspace $ws}
		}
		'System' {
				if(([String]::IsNullOrEmpty($subscription)) -or ([String]::IsNullOrEmpty($workspace)) -or ([String]::IsNullOrEmpty($ResourceGroup))) {Throw-EmptyDiscovery; Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("MIssing SubscriptionId, workspace or resourcegroup") $TRACE_ERROR	}
				$query = 'ObjectName!="Advisor Metrics" ObjectName!=ManagedSpace | measure max(TimeGenerated) as lastdata by Computer | where lastdata > NOW-{0}HOURS' -f $ValidHours
				Log-Event $INFO_EVENT_ID $EVENT_TYPE_SUCCESS ("About to query OMS with $query") $TRACE_VERBOSE
				$jsystems = Invoke-OMSSearchQuery -Token $token -SubscriptionId $subscription -ResourceGroupName $ResourceGroup -OMSWorkspaceName $workspace -Query $query
				foreach($sys in $jsystems) {
					Discover-System $sys
				}

		}
	}
	$discoveryData
	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		#it breaks in exception when run insde OpsMgr and POSH IDE	
		$g_API.Return($discoveryData)
	}
	#get all the subscriptions
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $Error) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
