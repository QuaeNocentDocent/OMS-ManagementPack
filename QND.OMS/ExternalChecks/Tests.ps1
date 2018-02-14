<#
$AADDomain='prelabs.onmicrosoft.com'
$subscriptionId='ec2b2ab8-ba74-41a0-bf54-39cc0716f414'
$credentials=Get-Credential -User svc_automation@prelabs.onmicrosoft.com -Message 'Workspace Account'
$resourceGroup='OI-Default-East-US'
$workspaceName='bbacc090-abbd-4313-9545-6dd72b96a1f6'

./Publish-HeartbeatEx.ps1 -AADDomain 'prelabs.onmicrosoft.com' -SubscriptionId 'ec2b2ab8-ba74-41a0-bf54-39cc0716f414' -ResourceGroup 'OI-Default-East-US' -WorkspaceName 'bbacc090-abbd-4313-9545-6dd72b96a1f6' -AutomationCRedentialName 'Lab Reggio Automation Account'
#> 