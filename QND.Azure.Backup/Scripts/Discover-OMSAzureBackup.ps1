## This discovery needs to be splitted 'cause potentially can discover a huge number of entities
## Gorup memeberhsip must be changed and split in diffrent rules using the properties we're setting

#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info
#https://azure.microsoft.com/en-us/documentation/articles/operational-insights-api-log-search/

#*************************************************************************
# Script Name - Discover-OMSAzureBackup
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
[Parameter (Mandatory=$false)] [String]$ExcludedVaults,
[String]$Proxyurl #nyi

)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Discover-OMSAzureBackup"
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


#id       : /subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault
#name     : Compliance-Vault
#type     : Microsoft.Backup/BackupVault
#location : westeurope
#tags     : 

#location   : westeurope
#name       : Infra-Vault
#etag       : 99e99335-e0a4-4b3e-91e3-f2021ba3ae49
#tags       : 
#properties : @{sku=; provisioningState=Succeeded}
#id         : /subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/eCloud-Infra/providers/Microsoft.Backup/BackupVault/Infra-Vault
#type       : Microsoft.Backup/BackupVault
#sku        :

Function Discover-BackupVault
{
	param($obj, $ResourceGroup, $Subscription)


	#$obj
	#$obj.properties

		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Backup.Vault']$")	

		$objInstance.AddProperty("$MPElement[Name='OMS!QND.OMS.Azure.Subscription']/Id$", $subscription)		

		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Id$", $obj.id)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Type$", $obj.type)	

		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Name$", $obj.name)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/ResourceGroup$", $ResourceGroup)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Subscription$", $Subscription)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Location$", $obj.location)
		
		if($obj.properties.sku) {$sku=$obj.properties.sku.name} else {$sku=$obj.sku}
		if([String]::IsNullOrEmpty($sku)){$sku=''}
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Sku$", $sku)	


		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.name)	
		$discoveryData.AddInstance($objInstance)	
}


# File system
#uniqueName    : brd-mcc-1.ecloud.lcl
#containerType : Machine
#properties    : @{containerId=305352; friendlyName=BRD-MCC-1.ECLOUD.LCL; containerStampId=ecdeb883-be8f-4cef-9185-66c870031055; 
#                containerStampUri=https://pod01-prot1.we.backup.windowsazure.com; canReRegister=False; customerType=OBS}

# IaasVM
#properties : @{friendlyName=brd-mcc-1; status=Registered; healthStatus=Healthy; containerType=IaasVM; parentContainerId=/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resou
#             rceGroups/RecoveryServices-MZGJTGR3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/microsoft.backup/BackupVault/BrdBackup/containers/brd-mcc}
#id         : /subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/RecoveryServices-MZGJTGR3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/micro
#             soft.backup/BackupVault/BrdBackup/containers/iaasvmcontainer;brd-mcc;brd-mcc-1
#name       : iaasvmcontainer;brd-mcc;brd-mcc-1
#type       : microsoft.backup/BackupVault/containers

# DPM Sources
#uniqueName    : fsrveuazbck01.furla.dom
#containerType : Machine
#properties    : @{containerId=482742; friendlyName=FSRVEUAZBCK01.FURLA.DOM; containerStampId=3f2a1395-55ed-4e55-8f40-de1f8a6c2a24; containerStampUri=https://pod01-prot1b.we.backup.windowsazure.com; 
#                canReRegister=False; customerType=DPMVenus}



Function Discover-BackupContainer
{
	param($obj, $subscription, $vaultName)

	#$obj

    try {
		if($obj.uniqueName) {
			$containerType=('{0}/{1}' -f $obj.ContainerType, $obj.properties.customerType )
			$id=$obj.UniqueName
			$name=$obj.UniqueName
			$type='microsoft.backup/MachineContainer'
			$displayName=$obj.properties.friendlyName
		}
		else {
			$containerType=$obj.properties.containerType
			$id=$obj.Id
			$name=$obj.Name
			$type=$obj.type
			$displayName=$obj.properties.friendlyName
		}

		$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Backup.Container']$")	
		$objInstance.AddProperty("$MPElement[Name='OMS!QND.OMS.Azure.Subscription']/Id$", $subscription)
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Name$", $vaultName)		

		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Id$", $id)	
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Type$", $type)	

		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Container']/Name$", $name)		
		$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Container']/ContainerType$", $containerType)	

		$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $displayName)	
		$discoveryData.AddInstance($objInstance)	
    }
    catch {
        Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocvering backup container {1} in vault {0} - {2}' -f $name, $Id, $Error[0]) $TRACE_WARNING	
	    write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	    Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
    }

}

#this was the item API response we now set on the protectedItem api
#properties : @{friendlyName=brd-mcc-1; itemType=IaasVM; status=Protected; containerId=/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/RecoveryServices-MZGJTGR
#             3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/microsoft.backup/BackupVault/BrdBackup/registeredContainers/iaasvmcontainer;brd-mcc;brd-mcc-1/it
#             ems/iaasvmcontainer;brd-mcc;brd-mcc-1}
#id         : /subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/RecoveryServices-MZGJTGR3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/micro
#             soft.backup/BackupVault/BrdBackup/registeredContainers/iaasvmcontainer;brd-mcc;brd-mcc-1/items/iaasvmcontainer;brd-mcc;brd-mcc-1
#name       : iaasvmcontainer;brd-mcc;brd-mcc-1
#type       : microsoft.backup/BackupVault/registeredContainers/items

#properties : @{protectionStatus=Protected; protectionPolicyId=/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVaul
#             t/Compliance-Vault/registeredContainers/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1/protectedItems/Weekly5; policyInconsistent=False; recoveryPointsCount=5; 
#             lastRecoveryPoint=2015-10-24T23:34:56.6351972Z; lastBackupTime=2015-10-24T23:32:48.6034936Z; lastBackupStatus=Completed; 
#             lastBackupJobId=841bbd72-af3d-4a0c-b496-aca4b4edc1d9; friendlyName=prg-mtr-crew1; itemType=IaasVM; status=Protected; containerId=/subscriptions/82fd323c-59e5-47f0-b
#             7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/registeredContainers/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1
#             /protectedItems/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1}
#id         : /subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/registeredContainers/iaasvmcon
#             tainer;prg-mtr-creweb;prg-mtr-crew1/protectedItems/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1
#name       : iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1
#type       : Microsoft.Backup/BackupVault/registeredContainers/protectedItems

Function Discover-BackupProtectedItem
{
	param($obj, $subscription, $vaultName, $container)

	#$obj
    try {
		if ($obj) {
			$objInstance = $discoveryData.CreateClassInstance("$MPElement[Name='QND.OMS.Backup.ProtectedItem']$")	
			$objInstance.AddProperty("$MPElement[Name='OMS!QND.OMS.Azure.Subscription']/Id$", $subscription)
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Vault']/Name$", $vaultName)		
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Container']/Name$", $container)	

			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Id$", $obj.id)		
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.Base']/Type$", $obj.type)	

			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.ProtectedItem']/Name$", $obj.name)	
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.ProtectedItem']/ItemType$", $obj.properties.itemType)	

#Write-Host $obj.properties
			$obj.properties.containerId -match '(^.*protectedItems\/)' | Out-Null
			$policyName=$obj.properties.protectionPolicyId.Replace($matches[0],'')
			$objInstance.AddProperty("$MPElement[Name='QND.OMS.Backup.ProtectedItem']/PolicyName$", $policyName)	

			$objInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $obj.properties.friendlyName)	
			$discoveryData.AddInstance($objInstance)	
		}
    }
    catch {
        Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocvering backup Item {2} in vault {0}\{1} - {3}' -f $vaultName, $container, $obj.Id, $Error[0]) $TRACE_WARNING	
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
    if (! ([String]::IsNullOrEmpty($ExcludedVaults))) {$exclusions = $ExcludedVaults.Split(',')}
    
	$discoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
    #first discover the accounts
	$uri='https://management.azure.com/subscriptions/{0}/resources?api-version=2014-04-01-preview&$filter=((resourceType eq ''microsoft.backup/BackupVault'') or (resourceType eq ''Microsoft.Backup/BackupVault''))' -f $subscriptionId
	$jres = Invoke-ARMGet -Token $token -Uri $uri
	if(! $jres) {Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Invoke-ARMGet failed $uri " + $Error) $TRACE_ERROR; exit 1;}
	foreach($vault in $jres.Value) {
        if ($exclusions -inotcontains $vault.Name) {
            #get vault details
            Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering Backup vault {0}' -f $vault.Name) -level $TRACE_VERBOSE
            try {
                $vault.Id -match '(?<=(resourceGroups\/))(?<Group>.*)(?=(\/providers))' | Out-Null
		        $ResourceGroup = $matches.Group                
                $uri='https://management.azure.com{0}?api-version=2015-03-15' -f $vault.Id
                $vaultDet = Invoke-ARMGet -Token $token -Uri $uri
                Discover-BackupVault -obj $vaultDet -ResourceGroup $ResourceGroup -Subscription $SubscriptionId
            }
            catch {
                Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocverying vault {0} - {1}' -f $vault.name, $Error[0]) $TRACE_WARNING	
	            write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	            Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
                continue;
            }
            try {
                #now discover the containers for this account
				$uri='https://management.azure.com{0}/backupContainers?&api-version=2015-03-15' -f $vault.Id
                $containers = Invoke-ARMGet -Token $token -Uri $uri
                foreach($container in $containers.Value) {      
                    Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering container {1} in backup vault {0}' -f $vault.Name, $container.UniqueName) -level $TRACE_VERBOSE              
                    Discover-BackupContainer -obj $container -subscription $SubscriptionId -vaultName $vault.Name
                } 
				$uri='https://management.azure.com{0}/containers?&api-version=2015-03-15' -f $vault.Id
                $containers = Invoke-ARMGet -Token $token -Uri $uri
				$uri='https://management.azure.com{0}/protectedItems?api-version=2014-09-01' -f $vault.Id
				$items = @((Invoke-ARMGet -Token $token -Uri $uri).Value)
                foreach($container in $containers.Value) {      
					if ($container.properties.healthStatus -ieq 'Deleted') {continue}
                    Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering container {1} in backup vault {0}' -f $vault.Name, $container.Name) -level $TRACE_VERBOSE              
                    Discover-BackupContainer -obj $container -subscription $SubscriptionId -vaultName $vault.Name
					#now disocver protcted items 
					try {
						#$uri='https://management.azure.com{0}/containers?&api-version=2015-03-15' -f $vault.Id
						#$containerId='{0}/Items/{1}' -f ($container.Id).Replace('containers','registeredContainers'), $container.Name
						#$uri='https://management.azure.com{0}/protectedItems?api-version=2014-09-01&$filter=(containerId -eq ''{1}'')' -f $vault.Id, $containerId
						$containerId='{0}/protectedItems/{1}' -f ($container.Id).Replace('containers','registeredContainers'), $container.Name
						$cItems = $items | where {$_.properties.containerId -eq $containerId}
						foreach($item in $cItems) {      
							Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering backup item {2} in path {0}/{1}' -f $vault.Name, $container.Name, $item.Name) -level $TRACE_VERBOSE              
							Discover-BackupProtectedItem -obj $item -subscription $SubscriptionId -vaultName $vault.Name -container $container.Name
						}

					}
					catch {
						Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error discoverying backup item for {0}/{1} - {2}' -f $vault.Name, $container.Name, $Error[0]) $TRACE_WARNING	
						write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
						Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
						continue;
					}

                } 


            }
            catch {
                Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ('Error disocverying backup containers for vault {0} - {1}' -f $vault.name, $Error[0]) $TRACE_WARNING	
	            write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	            Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
                continue;
            }
        }
        else {Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Backup Vault {0} filtreed out' -f $vault.Name) -level $TRACE_INFO}
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
