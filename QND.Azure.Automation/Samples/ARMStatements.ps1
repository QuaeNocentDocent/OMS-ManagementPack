import-module "C:\Local\dev\OpsMgr\GIT\QND.OMS\QND.OMS\OMSSearch\OMSSearch.psm1"

	$AssemblyName = 'Microsoft.IdentityModel.Clients.ActiveDirectory'
	$AssemblyVersion = "2.14.0.0"
	$AssemblyPublicKey = "31bf3856ad364e35"

$dllpath='C:\Users\grandinid\SkyDrive\Dev\OpsMgr\GIT\QND.OMS\QND.OMS\OMSSearch\Microsoft.IdentityModel.Clients.ActiveDirectory.dll'
[Void][System.Reflection.Assembly]::LoadFrom($DLLPath)

$subid='ec2b2ab8-ba74-41a0-bf54-39cc0716f414'

$credential = Get-Credential
$token = Get-AADToken -TenantADName prelabs.onmicrosoft.com -Username $credential.UserName -Password ($credential.GetNetworkCredential()).Password
$token = Get-AADToken -TenantADName progelazureclioutlook.onmicrosoft.com -Username $credential.UserName -Password ($credential.GetNetworkCredential()).Password

$subid='82fd323c-59e5-47f0-b7c7-a16a4534d86a'

#list abckup vaults we can think of removing the old interface the lowercase one
$uri='https://management.azure.com/subscriptions/{0}/resources?api-version=2014-04-01-preview&$filter=((resourceType eq ''microsoft.backup/BackupVault'') or (resourceType eq ''Microsoft.Backup/BackupVault''))' -f $subid
$jres = Invoke-ARMGet -Token $token -Uri $uri

foreach($vault in $jres.value){
    write-Host $vault.Name
    $uri=('https://management.azure.com/{0}?api-version=2015-03-15' -f $vault.Id)
    $jvault = Invoke-ARMGet -Token $token -Uri $uri
    $jvault
    if($jvault.properties.sku) {write-host $jvault.properties.sku.Name} else {write-host $jvault.sku}
}

#get a list of containers
#Files and folders
$vaultId='/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault'

$vaultId='/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/RecoveryServices-MZGJTGR3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/microsoft.backup/BackupVault/BrdBackup'
$uri='https://management.azure.com{0}/backupContainers?&api-version=2015-03-15' -f $vaultId
$jres = Invoke-ARMGet -Token $token -Uri $uri

#IaaSVM
$uri='https://management.azure.com{0}/containers?&api-version=2015-03-15' -f $vaultID
$jres = Invoke-ARMGet -Token $token -Uri $uri



$uri='https://management.azure.com{0}/items?api-version=2014-09-01' -f $VaultId
$items = Invoke-ARMGet -Token $token -Uri $uri

$name='iaasvmcontainer;brd-mcc;brd-mcc-1'
#get a list of protected items
$containerId='/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/RecoveryServices-MZGJTGR3HYSFVA4K46SF7ZD4B7JO4XJSH7PJ6RTSPABBFXU74BGQ-west-europe/providers/microsoft.backup/BackupVault/BrdBackup/registeredContainers/iaasvmcontainer;brd-mcc;brd-mcc-1/items/iaasvmcontainer;brd-mcc;brd-mcc-1'

$uri='https://management.azure.com{0}/items?api-version=2014-09-01&$filter=(containerId -eq ''{1}'')' -f $VaultId, $containerId
$jres = Invoke-ARMGet -Token $token -Uri $uri

$vaultId='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup'


$uri='https://management.azure.com{0}/protectedItems?api-version=2014-09-01' -f $vaultId
$containerId='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/containers/iaasvmcontainer;pre-infrastructure;pre-webapp1'
$containerId='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/containers/iaasvmcontainer;pre-infrastructure;dclab02'
$containerId='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/RecoveryServices-HRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/microsoft.backup/BackupVault/pre-weu-backup/containers/iaasvmcontainer;pre-infrastructure;pre-adsync'

$containerName='iaasvmcontainer;pre-infrastructure;pre-adsync'
$cId='{0}/protectedItems/{1}' -f ($containerId).Replace('containers','registeredContainers'), $containerName

$uri='https://management.azure.com{0}?api-version=2014-09-01' -f $containerId
$uri='https://management.azure.com{0}/protectedItems?api-version=2014-09-01&$filter=(Name -eq ''iaasvmcontainer;pre-infrastructure;dclab02'')' -f $vaultId, $containerId
$jres = Invoke-ARMGet -Token $token -Uri $uri



#get a list of recovery points
$containerId='iaasvmcontainer;prg-cmp-bpm;cmp-bpm-web1'
$uri='https://management.azure.com/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/registeredContainers/iaasvmcontainer%3Bprg-cmp-bpm%3Bcmp-bpm-web1/protectedItems/{0}/recoveryPoints?api-version=2014-09-01' -f $ContainerId
$jres = Invoke-ARMGet -Token $token -Uri $uri

$itemId= ('/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/registeredContainers/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1/items/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1').Replace('items','protectedItems')
$uri='https://management.azure.com{0}/recoveryPoints?api-version=2014-09-01' -f $itemId
$recPoints = Invoke-ARMGet -Token $token -Uri $uri


#list backup jobs
https://management.azure.com/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/jobs?api-version
=2014-09-01&$filter=operation eq 'Backup' and startTime eq '2015-01-09 11:00:00 PM' and endTime eq '2015-10-28 07:48:34 AM'

#formatting date and time
$mytime=(get-date).ToUniversalTime()
$now=$myTime.ToString('yyyy-MM-dd hh:mm:ss tt')
#don't know why tt doens't work
#quick fix without reverting to -net framework formatting
if($now.IndexOf('M') -eq -1) {
    if ($myTime.Hour -lt 13) {$now+= 'AM'} else {$now += 'PM'}
}

$mytime=((get-date).ToUniversalTime()).AddDays(-15)
$then=$myTime.ToString('yyyy-MM-dd hh:mm:ss tt')
#don't know why tt doens't work
#quick fix without reverting to -net framework formatting
if($then.IndexOf('M') -eq -1) {
    if ($myTime.Hour -lt 13) {$then+= 'AM'} else {$then += 'PM'}
}


$uri='https://management.azure.com{0}/jobs?api-version=2014-09-01&$filter=operation eq ''Backup'' and startTime eq ''{1}'' and endTime eq ''{2}'' and WorkloadName -eq ''{3}''' -f $vaultId, '2015-10-01 07:00:00 AM', '2015-10-28 07:00:00 AM', 'prg-mtr-crew1'
$uri='https://management.azure.com{0}/jobs/{1}?api-version=2014-09-01' -f $vaultId, '841bbd72-af3d-4a0c-b496-aca4b4edc1d9'

$jres = Invoke-ARMGet -Token $token -Uri $uri

#job details
#get sul Job Id
$uri='https://management.azure.com/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/jobs/2365d2d4-4100-473d-8cfa-618bb070ea5a?api-version=2014-09-01'
$jres = Invoke-ARMGet -Token $token -Uri $uri

#get protecteditem policy
$protectionPolicyId='/subscriptions/82fd323c-59e5-47f0-b7c7-a16a4534d86a/resourceGroups/Compliance/providers/Microsoft.Backup/BackupVault/Compliance-Vault/registeredContainers/iaasvmcontainer;prg-mtr-creweb;prg-mtr-crew1/protectedItems/Weekly5'
$uri='https://management.azure.com{0}?api-version=2014-09-01' -f $protectionPolicyId
$jres = Invoke-ARMGet -Token $token -Uri $uri

$aaName=$jres.value.name
#get properties
$uri='https://management.azure.com/subscriptions/{0}/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/{1}?api-version=2015-01-01-preview' -f $subId, $aaName

$uri='https://management.azure.com/subscriptions/{0}/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts?api-version=2015-01-01-preview' -f $subId
$jres = Invoke-ARMGet -Token $token -Uri $uri

#properties in
$jres.properties.sku.name
$jres.properties.creationTime

#get runbooks
$uri='https://management.azure.com/subscriptions/{0}/resources?api-version=2014-04-01-preview&$filter=(resourceType eq ''microsoft.automation/automationaccounts/runbooks'')' -f $subId

#get runbooks properties
$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks/Tagetik-FirstConfig?api-version=2015-01-01-preview'
$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks?api-version=2015-01-01-preview'



$uri='https://s2.automation.ext.azure.com/api/Orchestrator/Jobs?compositeIdentifier=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE&pageLink=&isFirstPage=true'

#status
#11 Completed
#4 Failed
#7 Stopped
#9 Suspended

#job details
$uri='https://s2.automation.ext.azure.com/api/Orchestrator/Job?compositeIdentifier=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE&jobId=7b9d0b72-b9f2-4701-936f-0d5829641ce9' #&_=1445334087305'

#jobs for a given runbook
$uri='https://s2.automation.ext.azure.com/api/Orchestrator/JobsByRunbook?compositeIdentifier=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourcegroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE&runbookId=ASR-HybridAutomation&pageLink=&isFirstPage=true'


$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE/runbooks?api-version=2015-01-01-preview'

#APIs
Runbook
Job
Certificates
Credentials
Schedules
HybridWorkerGroups
JobsByRunbook
Variables
DscConfigurations
DscNodes
Modules
Connections


$lastnJobs=5
$maxFailures=0
$automationURI='https://s2.automation.ext.azure.com/api/Orchestrator'
$account=@{Id='/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE'}
                $uri='https://management.azure.com{0}/runbooks?api-version=2015-01-01-preview' -f $account.Id
                $runbooks = Invoke-ARMGet -Token $token -Uri $uri
                foreach($runbook in $runbooks.Value) {      
                    #Log-Event -eventID $INFO_EVENT_ID -eventType $EVENT_TYPE_INFORMATION -msg ('Discovering Runbook {1} in Automation Account {0}' -f $account.Name, $runbook.Name) -level $TRACE_VERBOSE              
                    
                    #get the last 5 jobs for the runbook and prepare the property bag
                    $uri='{0}/JobsByRunbook?compositeIdentifier={1}&runbookId={2}&pageLink=&isFirstPage=true' -f $automationURI, $account.Id, $runbook.Name
                    $jobs = Invoke-ARMGet -Token $token -Uri $uri
                    $lastJobs = @($jobs.Resources | Select-Object -First $lastnJobs)
                    $failures = @($lastJobs | where {$_.status -match '^[4|9]$'}).Count
                    if ($lastJobs.COunt -gt 0) {
                        $lastJobDurationMinutes= ([datetime]($lastJobs[0].EndTime) - [datetime]($lastJobs[0].createdTime)).TotalMinutes
                        $lastJobRuntimeMinutes= ([datetime]($lastJobs[0].EndTime) - [datetime]($lastJobs[0].startTime)).TotalMinutes
                        $lastJobStatus = $lastJobs[0].status
                        $lastJobExecutionTime = $lastJObs[0].endTime
                        $lastJobExecutionAge = ((Get-Date)- [datetime]($lastJObs[0].endTime)).TotalHours
                    } else {$lastJobStatus=-1; $lastJobDurationMinutes=-1; $lastJobRuntimeMinutes=-1; $lastJobExecutionTime=-1; $lastJobExecutionAge=-1}

                    write-host ('{0} - retunred jobs {1} selected jobs {2} failures {3} last job status {4} job duration {5} job run time {6} last Execution {7} age {8}' -f $runbook.Name, $jobs.resources.Count, $lastJobs.Count, $failures, $lastjobStatus, $lastJobDurationMinutes, $lastJobRuntimeMinutes, $lastJobExecutionTime, $lastJobExecutionAge)
                } 



#list webhooks
$uri='https://s2.automation.ext.azure.com/api/Orchestrator/WebhooksForRunbook?compositeIdentifier=/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourcegroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE&runbookName=Tagetik-InfraAzure'
$jres = Invoke-ARMGet -Token $token -Uri $uri