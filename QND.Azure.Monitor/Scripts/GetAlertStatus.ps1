
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
[ValidateRange(0,5)]
[int]$traceLevel,
[Parameter (Mandatory=$true)][string]$clientId,
[Parameter (Mandatory=$true)][string]$SubscriptionId,
[string]$Proxy,
[Parameter (Mandatory=$true)][string]$AuthBaseAddress,
[Parameter (Mandatory=$true)][string]$ResourceBaseAddress,
[Parameter (Mandatory=$true)][string]$ADUserName,
[Parameter (Mandatory=$true)][string]$ADPassword
)


	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
    [Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

#region Constants	
#Constants used for event logging
$SCRIPT_NAME	= "GetAzureMonitorAlertStatus"
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

function ConvertTo-HashTable
{
  param([object] $object)

  $retHash=@{}
  try {
    $props = $object | gm | where {$_.MemberType -match 'Property'}
    foreach($p in $props) {
      $retHash.Add($p.Name, $object.($p.name))
    }
  }
  catch {
    # do nothing
  }
  return $retHash
}
#endregion

#region specifics
#same code base of Get-MonitorAlertRules.ps1

Function GetMetricsRule
{
	param(
		$SubscriptionId,
		$timeout,
		$connection
	)
	$rules=@()
	$metricAlertsAPI='2018-03-01'
	$uri=('https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/metricAlerts?api-version={1}' -f $subscriptionId,$metricAlertsAPI)
	$nextLink=$null
	$body=$null
	do {
		$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)	
		write-verbose ('Got {0} metric rules' -f $result.values.count)
		foreach($rule in $result.Values) {
			if($rule.properties.Enabled) {
				$rules+= New-Object -TypeName PSCustomObject -Property @{
					Id = $rule.Id
					Name=$rule.Name
					Type=$rule.Type
					Description = $rule.properties.Description
					Kind = 'unknown'
					Location = $rule.Location
				}
				#Discover-AlertRule -Id $rule.Id -AlertName $rule.Name -AlertType $rule.Type -AlertDescription $rule.properties.Description -AlertKind 'unknown' -Location $rule.Location -SubscriptionId $SubscriptionId
			}
		}
	} while ($nextLink)	
	return $rules
}

Function GetActivityLogRules
{	
	param(
		$SubscriptionId,
		$timeout,
		$connection
	)
	$rules=@()
	$activityLogAPI='2017-04-01'
	
	$uri=('https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/activityLogAlerts?api-version={1}' -f $subscriptionId,$activityLogAPI)

	$nextLink=$null
	$body=$null
	do {
		$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
		write-verbose ('Got {0} activity log rules' -f $result.values.count)
		foreach($rule in $result.Values) {
			if($rule.properties.Enabled) {
				$rules+= New-Object -TypeName PSCustomObject -Property @{
					Id = $rule.Id
					Name=$rule.Name
					Type=$rule.Type
					Description = $rule.properties.Description
					Kind = $rule.Kind
					Location = $rule.Location
				}
			}
		}
	} while ($nextLink)
	return $rules
}

Function GetLogRules
{
	param(
		$SubscriptionId,
		$timeout,
		$ResourceBaseAddress,
		$connection
	)
	$rules=@()
		#first discover all the log analytics workspaces in the subscription
		$uri = '{0}/subscriptions/{1}/resources?$filter=resourceType EQ ''Microsoft.OperationalInsights/workspaces''&api-version=2016-09-01' -f $ResourceBaseAddress, $SubscriptionId
		$nextLink = $null
		$OMSAPIVersion='2015-03-20'
		$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
		foreach($workspace in $result.Values) {
			$resourceGroup=($workspace.id -split '/')[4]
			$resourceURI=$workspace.Id
	
			$uri = '{0}{1}/savedSearches?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
			$nextLink = $null
			$savedSearches=@()
			do {
				$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)
				$nextLink = $result.NextLink
				$savedSearches += $result.values	
			} while ($nextLink)
			write-verbose ('Got {0} saved searches' -f $savedSearches.count)
	
			foreach($search in $savedSearches) {
				$uri = '{0}{1}/schedules?api-version={2}' -f $ResourceBaseAddress,$search.Id,$OMSAPIVersion
				$nextLink=$null
				$schedule = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $extLink -data $null -TimeoutSeconds $timeout -ErrorAction SilentlyContinue -Verbose:($PSBoundParameters['Verbose'] -eq $true)
				if($schedule.values) {			
					#take into account just the first schedule for the search maybe this needs to be changed in future
					if ($schedule.Values[0].properties.Enabled -ieq 'True') {
					   $uri = '{0}{1}/actions?api-version={2}' -f $ResourceBaseAddress,$schedule.values[0].id,$OMSAPIVersion
					   $nextLink=$null			   
					   $actions = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)				   
					   if ($actions.Values) {
							foreach($action in $actions.Values) {
								if ($action.properties.Type -ieq 'Alert') {
									$alertType='Standard'
									try { if($action.properties.Threshold.MetricsTrigger) {$alertType='MetricBased'}} catch {}
									if ([String]::IsNullOrEmpty($action.properties.Description)) {$AlertDescription='n.a.'} else {$alertDescription=$action.properties.Description}
									$rules+= New-Object -TypeName PSCustomObject -Property @{
										Id = $schedule.Values[0].id
										Name=$action.properties.Name
										Type='Microsoft.OperationalInsights'
										Description = $AlertDescription
										Kind = $alertType
										Location = 'n.a.'
									}
								}
							}
					   }
					}
				}
			}
			
		}
		return $rules
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
        Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Cannot get Azure AD connection aborting $Error") $TRACE_ERROR
        exit 1	
    }
try
{

	$error.clear() #let's use this like a catch all
	$rules=@()
	#first discover metrics
	#$rules = GetMetricsRule -SubscriptionId $SubscriptionId -timeout $timeout -connection $connection
	#then discovery Activity Log Alerts
	#$rules += GetActivityLogRules -SubscriptionId $SubscriptionId -timeout $timeout -connection $connection
	#last discover Log rules
	#$rules += GetLogRules -SubscriptionId $SubscriptionId -timeout $timeout -ResourceBaseAddress $ResourceBaseAddress -connection $connection

    #now get all the alerts
    $api='2018-05-05-preview'
    $uri = '{0}/subscriptions/{1}/providers/Microsoft.AlertsManagement/alerts?api-version={2}' -f $ResourceBaseAddress, $SubscriptionId, $api
	$nextLink=$null
    $alerts=@()
	do {
		$result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)	
        write-verbose ('Got {0} alerts' -f $result.values.count)
        $alerts+=$result.Values
	} while ($nextLink)	

    foreach($alert in $alerts) {
        if($alert.properties.monitorService -ieq 'Log Analytics') {
            #get correlation id
            $uri = '{0}/{1}?api-version={2}' -f $ResourceBaseAddress, $alert.id, $api 
            $result=invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $null -TimeoutSeconds $timeout -Verbose:($PSBoundParameters['Verbose'] -eq $true)	
            if($result.Values.count -gt 0) {
                $detail = $result.Values[0].properties.payload               
                $ruleKey = 'subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationalInsights/workspaces/{2}/savedSearches/{3}/schedules/{4}' `
                    -f $SubscriptionId, $detail.TargetResourceGroup, $detail.TargetResourceName, $detail.SavedSearchId, $detail.ScheduledSearchId
            }
        }
        else {
            $ruleKey = $alert.properties.sourceCreatedId
        }

        $returnBag = @{
            RuleId = $ruleKey
            State = $alert.properties.State
            AlertState = $alert.properties.AlertState
            monitorCondition = $alert.properties.monitorCondition
        }

        Return-Bag -object $returnBag -key RuleId 
    }

    if($traceLevel -eq $TRACE_DEBUG) {
        write-warning 'Exception expected if run inside powershell ISE'
        $g_API.ReturnItems()
    }

	Log-Event -eventID $EVENT_ID_STOP -eventType $EVENT_TYPE_INFORMATION -msg ('{0} has completed successfully in {1} seconds.' -f $SCRIPT_NAME, ((Get-Date)- ($dtstart)).TotalSeconds) -level $TRACE_INFO
}
Catch [Exception] {
	Log-Event -eventID $EVENT_ID_FAILURE -eventType $EVENT_TYPE_ERROR -msg ("Main got error: {0} for {1}" -f $Error[0],$SubscriptionId) -level $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
