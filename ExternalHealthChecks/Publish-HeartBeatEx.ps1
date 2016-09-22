#
# Publish-HeartbeatEx.ps1
# Draft
#
[CmdletBinding()]
param(
    [Parameter (Mandatory=$false)]
    [string] $ResourcebaseAddress='https://management.azure.com/',
    [Parameter (Mandatory=$true)]
    [string] $SubscriptionId,
    [Parameter (Mandatory=$true)]
    [string] $ResourceGroup,
    [Parameter (Mandatory=$true)]
    [string] $WorkspaceName,
    [Parameter (Mandatory=$false)]
    [string] $ApiVersion='2015-03-20',

    <# Azure automation doesn't support parameterset yet 
    [Parameter(ParameterSetName='Secure')] #>
    [PSCredential] $Credentials,
    #[Parameter(ParameterSetName='Rest')]
    [Parameter (Mandatory=$false)]
    [string] $AADDomain,
    #[Parameter(ParameterSetName='Rest')]
    [Parameter (Mandatory=$false)]
    [string] $ClientId='1950a258-227b-4e31-a9cf-717495945fc2', # Set well-known client ID for Azure PowerShell
    #if set we assume we're using a ServicePrincipal
    [String] $TenantId='7217effd-aa40-4bdd-8114-33c6b6a0116e',
    #[Parameter(ParameterSetName='Unsecure')]
    [string] $UserName,
    #[Parameter(ParameterSetName='Unsecure')]
    [string] $Password,
    #[Parameter(ParameterSetName='Automation')]
    [string] $AutomationCredentialName='EDSB2C Automation Account',
    #[Parameter(ParameterSetName='AutomationConnection')]
    [string] $AutomationConnectionName,

    [Parameter (Mandatory=$false)]
    [switch] $crossed=$false,
    [Parameter (Mandatory=$false)]
    [int] $observeDays=1,
    [switch] $RestOnly=$false,
    [Parameter (Mandatory=$false)]
    [string[]] $excludedTypes=@('QNDHeartbeatEx_CL','NetworkSecurityGroup'),
    [Parameter (Mandatory=$false)]
    [string] $excludedComputers=''
)

#$VerbosePreference='Continue'


Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
        $xHeaders = "x-ms-date:" + $date
        $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($sharedKey)

        $sha256 = New-Object System.Security.Cryptography.HMACSHA256
        $sha256.Key = $keyBytes
        $calculatedHash = $sha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($calculatedHash)
        $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
        return $authorization
    }

Function Post-OMSData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        #"time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}

Function Return-Results
{
param(
$ResourceGroupName,
$WorkspaceName,
$query,
$start,
$end,
$top=0)

$response = Get-AzureRmOperationalInsightsSearchResults -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -Query $query -Start $Start -End $End -Top $top
if ($response.Id -match '.*\/(?''id''.*?)$') {$id = $Matches['id']}

# Poll if pending
while($response.Metadata.Status -eq "Pending" -and ! $response.Error.Type -and $id) {
    Start-Sleep -Seconds 5
    $response = Get-AzureRmOperationalInsightsSearchResults -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroupName -Query $query -Id $id -Top $top
}

return $response
}

#todo aprameter validation
#todo - add user interaction to select subscription and workspace
if(!([String]::IsnullOrEmpty($AutomationConnectionName))) {
    $connection=Get-AutomationConnection -Name $AutomationConnectionName
 "Logging in to Azure..."
   Add-AzureRmAccount `
     -ServicePrincipal `
     -TenantId $connection.TenantId `
     -ApplicationId $connection.ApplicationId `
     -CertificateThumbprint $connection.CertificateThumbprint 
   "Setting context to a specific subscription"  
   Set-AzureRmContext -SubscriptionId $connection.SubscriptionId  
    $subscriptionId=$connection.SubscriptionId
    $ClientId=$connection.ApplicationId
}
else {
#if ($PSCmdlet.ParameterSetName -ieq 'Unsecure') {
if(!$Credentials) {
    if($AutomationCredentialName) {
        $credentials= Get-AutomationPSCredential -Name $AutomationCredentialName
    }
    else {
        $pwd = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credentials = New-Object System.Management.Automation.PSCredential ($Username, $pwd)
    }
}
}
if ($RestOnly) {
if (! (get-module QNDAdal)) {Import-module QNDAdal}
if (! (Get-Module QNDAzure)) {import-module QNDAzure}

$authBaseAddress=('https://login.windows.net/{0}/' -f $AADDomain)
$resourceUri='/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationalInsights/workspaces/{2}' -f $SubscriptionId, $ResourceGroup, $WorkspaceName
try {
$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress -clientId $clientId -credential $Credentials
#$authority = Get-AdalAuthentication -resourceURI $resourcebaseAddress -authority $authBaseAddress

$connection=$authority.CreateAuthorizationHeader()
}
catch {
    Write-Error ('Authentication Failed {0}' -f $_)
    throw($_)
    #logging todo
}

#get the workspace ID and in future let browse for the workspace
# list https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OI-Default-East-US/providers/Microsoft.OperationalInsights/workspaces?api-version=2015-11-01-preview
    $uri='{0}{1}?api-version={2}' -f $ResourcebaseAddress, $resourceUri, $ApiVersion
	$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb GET -authToken $connection -nextLink $null -TimeoutSeconds $timeoutSeconds
    if(! $result -or $result.StatusCode -ne 200) {
        throw (('error getting workspace id {0}'-f $error[0]))
    }
    $workspaceID=$result.Values.properties.customerId    
#get keys
    $uri='{0}{1}/sharedKeys?api-version={2}' -f $ResourcebaseAddress, $resourceUri, $ApiVersion
	$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken $connection -nextLink $null -TimeoutSeconds $timeoutSeconds
    if(! $result -or $result.StatusCode -ne 200) {
        throw (('error getting workspace id {0}'-f $error[0]))
    }
    $workspaceKey=$result.Values.primarySharedKey
}
else {
    If(!(Get-Module -Name AzureRM.OperationalInsights)){Import-Module AzureRM.OperationalInsights}
    if(!(get-Module -Name AzureRM.Profile)){Import-Module AzureRM.Profile}
    try {
    if($Credentials) {
        IF([String]::IsnullOrEmpty($TenantId)) {
            Add-AzureRmAccount -Credential $credentials -SubscriptionId $SubscriptionId | Out-Null
        }
        else {
            write-verbose 'Using Service Principal Account'
            Add-AzureRmAccount -ServicePrincipal -TenantId $TenantId -Credential $credentials -SubscriptionId $SubscriptionId -EnvironmentName AzureCloud |Out-NUll
            #Get-AzureRmSubscription
        }
    }
    else {Login-AzureRmAccount}

    Select-AzureRmSubscription -SubscriptionId $SubscriptionId | out-NUll
    }
    catch {
        $_
        throw ('Cannot logon to subscription {0}' -f $Error[1].InnerException)
    }
    $workspaceId=(Get-AzureRmOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroup).CustomerId
    $workspaceKey=(Get-AzureRmOperationalInsightsWorkspaceSharedKeys -Name $WorkspaceName -ResourceGroupName $ResourceGroup).PrimarySharedKey
}        

$to=(Get-Date).ToUniversalTime()
$from=$to.AddDays(-$observeDays)
#Step 1 get contributing Types for the workspace  in the last day
$query='* | measure count() by Type'
if($RestOnly) {
    $result = Get-QNDOMSQueryResult -query $query -startDate $from -endDate $to -timeout $timeout -authToken $connection `
	    -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $apiVersion
}
else {
    $response = Return-Results -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Query $query -Start $from -End $to
    $result=@()
    $response.Value | %{$result+=ConvertFrom-Json $_}
    #$result = Get-AzureRmOperationalInsightsSearchResults -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $Result.Id
}

	$expectedTypes=@()
	$result | %{$expectedTypes+=$_.Type}
    $expectedTypes = $expectedTypes | ?{$_ -notin $excludedTypes}
	$query='* | measure max(TimeGenerated) As LastData, count() As Points by Computer, Type | sort Computer'
if($RestOnly) {
	$resultTable = Get-QNDOMSQueryResult -query $query -startDate $from -endDate $to -timeout $timeout -authToken $connection `
	    -ResourceBaseAddress $ResourceBaseAddress -resourceURI $resourceURI -OMSAPIVersion $apiVersion
}
else {
    $response = Return-Results -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Query $query -Start $from -End $to #-Top 99999
    $resultTable=@()
     $response.Value | %{$resultTable+=ConvertFrom-Json $_}
}

    #now probably there's a better way, but let's make it working and then let's think about optimizations
    #let's work an a case insensitive list of computers, this is the main reason to have this custom ingestion
    $computers = ($resultTable | select -Unique @{Name='Computer';Expression={$_.Computer.ToLower()}}) 
    
    if(![String]::IsNullOrEmpty($excludedComputers)){$computers= $computers| ?{$_ -notmatch $excludedComputers}}
    #set computer name to lower, not a good idea if we want to match to HeartBeat
    #$resultTable | select @{Name='Computer';Expression={$_.Computer.Tolower()}}, * -ExcludeProperty @('Computer')
    foreach($computer in $computers) {
        $part=@()
        $resultTable.where({$_.Computer -ieq $computer.Computer},[System.Management.Automation.WhereOperatorSelectionMode]::Default)| %{$part+=$_.Type}
        $missingTypes=$expectedTypes.Where({$part -inotcontains $_})
        $computerMatch = ($resultTable | ?{$_.Computer -ieq $computer.Computer -and $_.Type -ieq 'Heartbeat'}).Computer
        if (!$computerMatch) {$computerMatch = $computer.Computer}
        $missingTypes | %{$resultTable += New-Object –TypeName PSObject –Prop (@{Computer=$computerMatch;Type=$_;LastData='2000-01-01T00:00:00Z';Points=0})}
    }

<#
    now it's just a matter of sending the data to the workspace, the payload will be similar to the following to accomodate a query that tells us if an agent is not reporting the expected data
    meta schema for crossed
    {
        "Computer":  <<computername>>,
        <<Type>>_LastData:  "2016-09-16T13:40:11.94Z", #Last Data point collecetd for <<Type>> 2000-01-01T00:00:00Z if don't have any data
        <<Type>>_Points:  56498.0 #data point collected in the last 24 hours for <<Type>> 0 if we don't have any data
    }

    meta schema for straight
    {
        "Computer":  <<computername>>,
        "Type": <<Type>>,
        "LastData":  "2016-09-16T13:40:11.94Z", #Last Data point collecetd for <<Type>> 2000-01-01T00:00:00Z if don't have any data
        "Points":  56498.0 #data point collected in the last 24 hours for <<Type>> 0 if we don't have any data
    }

    Type:QNDHeartbeatEx_CL Points_d = 0 (Type_s=Event OR Type_s=SecurityEvent OR Type_s=Perf OR Type_s=Heartbeat OR Type_s=Syslog) | measure sum(Points_d) by Computer, Type_s
#>
    if($crossed) {
        $crossedTable=@()
        foreach($computer in $computers) {
            $rows = $resultTable | ?{$_.Computer -ieq $computer.Computer}
            $element=New-Object –TypeName PSObject –Prop (@{Computer=$computer.Computer})
            foreach($row in $rows) {
                $element | add-Member -NotePropertyName "$($row.Type)_LastData" -NotePropertyValue $row.LastData
                $element | add-Member -NotePropertyName "$($row.Type)_Points" -NotePropertyValue $row.Points
            }
            $crossedTable+=$element
        }
        $payLoad = convertto-json $crossedTable
        $logType = 'QNDHeartbeatExCrossed'
    }
    else {$payLoad = convertto-json $resultTable;$logType='QNDHeartbeatEx'}


    Post-OMSData -customerId $workspaceID -sharedKey $workspaceKey -body $payLoad -logType $logType


