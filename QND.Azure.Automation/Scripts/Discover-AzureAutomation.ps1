#$guid='{{{0}}}' -f (new-guid).guid

## This discovery needs to be splitted 'cause potentially can discover a huge number of entities
## Gorup memeberhsip must be changed and split in diffrent rules using the properties we're setting

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/

#*************************************************************************
# Script Name - Discover-AzureAutomation
# Author	  - Daniele Grandini
# Version  - 1.0 20.10.2015
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
[Parameter (Mandatory=$true)] [String]$SubscriptionId,
[Parameter (Mandatory=$true)] [String]$Username,
[Parameter (Mandatory=$true)] [String]$Password,
[Parameter (Mandatory=$false)] [String]$ExcludedAccounts,
[String]$Proxyurl #nyi

)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Disocver-AzureAccount"
$SCRIPT_ARGS = 9
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


#id       : /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automati
#           on/automationAccounts/PreLabsAutoWE
#name     : PreLabsAutoWE
#type     : Microsoft.Automation/automationAccounts
#location : westeurope
#tags     : 

#name       : PreLabsAutoWE
#id         : /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automa
#             tion/automationAccounts/PreLabsAutoWE
#type       : Microsoft.Automation/AutomationAccounts
#location   : West Europe
#tags       : 
#etag       : 
#properties : @{sku=; state=Ok; creationTime=2015-03-18T16:42:16.713+00:00; lastModifiedBy=; lastModifiedTime=2015-10-19T11:02:30.847+00:00}

Function Discover-AutomationAccount
{
	param($obj, $ResourceGroup, $Subscription)

		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Automation.Account']$")	
		$objInstance.AddProperty("$MPElement[Name='OMS!QND.OMS.Azure.Subscription']/Id$", $subscription)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Id$", $obj.Id)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Name$", $obj.Name)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/ResourceGroup$", $ResourceGroup)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Subscription$", $Subscription)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Location$", $obj.location)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Type$", $obj.type)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Sku$", $obj.properties.sku.name)	

		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.Name)	
		$discoveryData.AddInstance($objInstance)	
}


#id         : /subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automa
#             tion/automationAccounts/PreLabsAutoWE/runbooks/Tagetik-FirstConfig
#name       : Tagetik-FirstConfig
#type       : Microsoft.Automation/AutomationAccounts/Runbooks
#location   : West Europe
#tags       : 
#etag       : "635772989264900000"
#properties : @{description=Cross cloud DSC configuration; logVerbose=False; logProgress=False; logActivityTrace=1; runbookType=Script; parameters=; state=Edit; jobCount=9; 
#             provisioningState=; serviceManagementTags=; creationTime=2015-09-03T14:41:21.733+00:00; lastModifiedBy=live.com#daniele.grandini@live.it; 
#             lastModifiedTime=2015-09-08T08:48:46.49+00:00}

#PS C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.OMS\OMSSearch> $jres.properties

#description           : Cross cloud DSC configuration
#logVerbose            : False
#logProgress           : False
#logActivityTrace      : 1
#runbookType           : Script
#parameters            : @{AzureSubscription=; adminPassword=; publicPort=; LocalAdmin=; ConfigName=; publicDnsName=; assetsRG=; assetsStg=; assetName=; assetsContainer=; 
#                        destinationFolder=}
#state                 : Edit
#jobCount              : 9
#provisioningState     : 
#serviceManagementTags : 
#creationTime          : 2015-09-03T14:41:21.733+00:00
#lastModifiedBy        : live.com#daniele.grandini@live.it
#lastModifiedTime      : 2015-09-08T08:48:46.49+00:00


Function Discover-AutomationRunbook
{
	param($obj, $subscription, $account)

    try {
	if ([String]::IsNullOrEmpty($obj.Name)) {return;}
		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Automation.Runbook']$")	
		$objInstance.AddProperty("$MPElement[Name='OMS!QND.OMS.Azure.Subscription']/Id$", $subscription)
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Account']/Name$", $account)		

		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Runbook']/Id$", $obj.Id)	
        $objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Runbook']/Name$", $obj.Name)	
        $objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Runbook']/Type$", $obj.Type)	
        $objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Runbook']/Location$", $obj.Location)	
        $objInstance.AddProperty("$MPElement[Name='QND.OMS.Automation.Runbook']/RunbookType$", $obj.Properties.runbookType)	

		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.Name)	
		$discoveryData.AddInstance($objInstance)	
    }
    catch {
        Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocverying runbook {1} in account {0} - {2}' -f $account.name, $obj.Id, $Error[0]) $TRACE_WARNING	
	    write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	    Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
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

try
{
    $exclusions=@()
    if (! ([String]::IsNullOrEmpty($ExcludedAccounts))) {$exclusions = $ExcludedAccounts.Split(',')}
    
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
    #first discover the accounts
	$uri='https://management.azure.com/subscriptions/{0}/resources?api-version=2014-04-01-preview&$filter=(resourceType eq ''microsoft.automation/automationaccounts'')' -f $SubscriptionId
	$jres = Invoke-ARMGet -Token $token -Uri $uri
	if(! $jres) {Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Invoke-ARMGet failed $uri " + $Error) $TRACE_ERROR; exit 1;}
	foreach($account in $jres.Value) {
        if ($exclusions -inotcontains $account.Name) {
            #get account details
            Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering Automation Account {0}' -f $account.Name) -level $TRACE_VERBOSE
            try {
                $account.Id -match '(?<=(resourceGroups\/))(?<Group>.*)(?=(\/providers))'
		        $ResourceGroup = $matches.Group
                #$uri='https://management.azure.com/subscriptions/{0}/resourceGroups/{2}/providers/Microsoft.Automation/automationAccounts/{1}?api-version=2015-01-01-preview' -f $SubscriptionId, $account.name, $resourceGroup
                $uri='https://management.azure.com{0}?api-version=2015-01-01-preview' -f $account.Id
                $accountDet = Invoke-ARMGet -Token $token -Uri $uri
                Discover-AutomationAccount -obj $accountDet -ResourceGroup $ResourceGroup -Subscription $SubscriptionId
            }
            catch {
                Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocverying account {0} - {1}' -f $account.name, $Error[0]) $TRACE_WARNING	
	            write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	            Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
                continue;
            }
            try {
                #now discover the runbooks for this account

                $uri='https://management.azure.com{0}/runbooks?api-version=2015-01-01-preview' -f $account.Id
                $runbooks = Invoke-ARMGet -Token $token -Uri $uri
                foreach($runbook in $runbooks.Value) {      
                    Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering Runbook {1} in Automation Account {0}' -f $account.Name, $runbook.Name) -level $TRACE_VERBOSE              
                    Discover-AutomationRunbook -obj $runbook -subscription $SubscriptionId -account $account.Name
                } 
            }
            catch {
                Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocverying runbooks for account {0} - {1}' -f $account.name, $Error[0]) $TRACE_WARNING	
	            write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	            Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
                continue;
            }
        }
        else {Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Automation Account {0} filtreed out' -f $account.Name) -level $TRACE_INFO}
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
