
<#
.Synopsis
   Executes a Microsoft Graph query
.DESCRIPTION
   Executes a Microsoft Graph Query and retruns a complex object
.EXAMPLE
   Get-ProgelAdmins -Customer UnCliente -OutFile c:\temp\test1.csv
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Invoke-QNDAzureRestRequest 
{
[CmdletBinding()]
[OutputType([object[]])]
param(
 [Parameter(ParameterSetName='managementUri')]
 [string] $managementUri='https://management.azure.com',
 [Parameter(ParameterSetName='managementUri')] 
 [string] $apiVersion='2015-01-01',
 [Parameter(Mandatory=$true,ParameterSetName='managementUri')]
 [string] $resourceType,
 [Parameter(Mandatory=$false,ParameterSetName='managementUri')]
 [string] $query,
 [Parameter(Mandatory=$true,ParameterSetName='singleUri')]
 [string] $uri,
 [string] $HTTPVerb='GET',
 [object] $data=$null, 
 [string] $proxy,
 [int] $timeoutSeconds=120,
 [Parameter(Mandatory=$true)][string] $authToken,
 [Parameter(Mandatory=$false)][string]$nextLink
)

    if ([String]::IsNullOrEmpty($authToken)) {
        throw "Graph Connection not properly intialized call Get-AdalAuthentication first"
    }

    try {
    $headers = @{"Authorization"=$authToken;"Content-Type"="application/json";"Accept"="application/json"}
    if($resourceType) {
        if (! [String]::IsNullOrEmpty($query)) {
            #$query = '?' + [System.Web.HttpUtility]::UrlEncode($query)
            $query= ('?api-version={0}&{1}' -f $apiVersion, $query)
        }
        else {
            $query= ('?api-version={0}' -f $apiVersion)
        }
        $startUri = [string]::Format("{0}/{1}{2}",$managementUri,$resourceType, $query)
    }
    else {$startUri=$uri}
    $body=$null
    if($data){
        write-verbose 'We have a body to process...'
        $enc = New-Object "System.Text.ASCIIEncoding"
        if ($Data.GetType().FullName -ne [String].FullName) {$body = ConvertTo-Json -InputObject $Data -Depth 10}
        else {$body=$data}
        Write-verbose $body
        $byteArray = $enc.GetBytes($body)
        $contentLength = $byteArray.Length
        $headers.Add("Content-Length",$contentLength)
    }
    if ($nextLink) {
        if($nextLink.Substring(0,4) -ieq 'http') {$restUri=$nextLink}
        else {$restUri = $startUri+$nextLink}
    }
    else {$restUri=$startUri}
    Write-Verbose ('HTTP {0} {1}' -f $HTTPVerb, $restUri)
    Write-Verbose 'Dumping Headers...'
    $headers.GetEnumerator() | % {Write-Verbose ('{0}: {1}' -f $_.Key, $_.Value)}
    }
    catch {
        Write-Error ('Exception processing URI and body {0}' -f $_.GetType().FullName)
        return $null
    }
    try {
        $nl=$null
		$gotValue=$false
        if ($proxy) {
            $result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing -Proxy $proxy
        }
        else {
            $result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing
        }
        write-verbose $result
        if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){        
            Write-Verbose "Query successfully executed $($result.StatusCode)."
            if($result.Content -ne $null){
                $json = (ConvertFrom-Json $result.Content)
                if($json -ne $null){
                    $nl = [System.Web.HttpUtility]::UrlDecode($json.nextLink)
                    if ($nl) {$nl=$nl.Replace($restUri,'')}
                    [array]$returnValues = $json
                    if($json.value -ne $null){
						[array]$returnValues = $json.value
						$gotValue=$true
					}
                }
            }
        }
		else {
			$returnValues=$null
			$nl=$null
		}
        $StatusCode=$result.StatusCode
      $returnObject = new-object -TypeName PSCustomObject -Property @{
        'Values' = $returnValues
        'NextLink' = $nl
        'StatusCode' = $StatusCode
		'GotValue' = $gotValue
        }
    }
    catch {
        Write-Error ('Exception processing query {0}' -f $_.GetType().FullName)
        Write-Verbose $_
        $nl=$null
        if ($result) {$StatusCode=$result.StatusCode}
        else {
            $StatusCode=500
            [array]$returnValues = $_.Message
        }
    }
	finally {
          $returnObject = new-object -TypeName PSCustomObject -Property @{
            'Values' = $returnValues
            'NextLink' = $nl
            'StatusCode' = $StatusCode
		    'GotValue' = $gotValue
        }
	}
    
  return $returnObject
}
