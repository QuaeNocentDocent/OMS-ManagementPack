
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
 [Parameter(Mandatory=$false)][PSCredential] $proxyCred,
 [int] $timeoutSeconds=120,
 [Parameter(Mandatory=$true)][string] $authToken,
 [Parameter(Mandatory=$false)][string]$nextLink,
 [Parameter(Mandatory=$false)][Hashtable]$otherHeader=@{"Content-Type"="application/json";"Accept"="application/json"}
)

    if ([String]::IsNullOrEmpty($authToken)) {
        throw "Graph Connection not properly intialized call Get-AdalAuthentication first"
    }

    try {
    if(! $otherHeader){$otherHeader=@{}}
    $headers = @{"Authorization"=$authToken;} + $otherHeader
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
            if($proxyCred) {$result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing -Proxy $proxy -ProxyCredential $proxyCred}
            else {$result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing -Proxy $proxy}
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

#to be implemented with body, proxy and other constructs
function Invoke-QNDAzureStorageRequest
{
[CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$uri,
        [Parameter(Mandatory=$true)]
        [string]$verb,
        [Parameter(Mandatory=$false)]
        [string]$key,
        [Parameter(Mandatory=$false)]
        [string]$version='2015-02-21',
        [Parameter(Mandatory=$false)]
        [string]$rootTag='EnumerationResults',
        [Parameter(Mandatory=$true)]
        [string]$searchTag,
        [int] $timeoutSeconds=60
    )

    # Building Authorization Header for Storage Account
    $returnObject = new-object -TypeName PSCustomObject -Property @{
        'ParsedValues' = $null
        'LastContent'=$null
        'StatusCode' = 500
		'GotContent' = $false
    }
    
    try {
        $verb=$verb.ToUpper()
        $uriparser= new-object System.Uri -ArgumentList @($uri)
        $saName = ($uriparser.Host.Split('.'))[0]
        $containerName = $uriparser.AbsolutePath
        $restParameters = $uriParser.Query.Replace('?','').Split('&')
        $restParameters = $restParameters | Sort
        # Time in GMT

        $Now = [System.DateTime]::UtcNow.ToString("R")

        # String to be signed with storage account key
        $signatureSb = New-Object System.Text.StringBuilder
        $null = $signatureSb.Append(("{0}`n`n`n`n`napplication/xml`n`n`n`n`n`n`nx-ms-date:{1}`nx-ms-version:{4}`n/{2}{3}" -f $verb, $Now, $saName, $containerName, $version )) 
        $restParameters | %{$null=$signatureSb.Append("`n$($_.Replace('=',':'))")}

        write-verbose ('COnstructing signature for {0}' -f $signatureSb.ToString())
        # Signing string with SA key UTF8 enconded with HMAC-SHA256 algorithm
        [byte[]]$signatureStringByteArray=[Text.Encoding]::UTF8.GetBytes($signatureSb.ToString())
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,[convert]::FromBase64String($key))
        $signature = [Convert]::ToBase64String($hmacsha.ComputeHash($signatureStringByteArray))
    }
    catch {
        Write-Error ('Exception computing signature {0}' -f $_.GetType().FullName)
        Write-Verbose $_
        $returnObject.Values=$_.Message
        return $returnObject
    }
    try {
        $headers=@{
            'Authorization'= "SharedKey $saName`:$signature"
            'Content-Type'='application/xml'
            'x-ms-date'="$Now"          
            'x-ms-version'=$version  
           }
           $fullbody=@()
           $broken=$false
           $nextMarker=''
        do {
            if(! [String]::IsNullOrEmpty($nextMarker)) { if($restParameters) {$completeUri='{0]&marker={1}' -f $uri,$nextMarker} else {$completeUri='{0]?marker={1}' -f $uri,$nextMarker}}
            else {$completeUri=$uri}
            $result=invoke-webrequest -Uri $uri -Headers $headers -Method $verb -ContentType application/xml -UseBasicParsing -TimeoutSec $timeoutSeconds
            write-verbose $result
            if($result.StatusCode -ge 200 -and $result.StatusCode -le 399){        
                Write-Verbose "Query successfully executed $($result.StatusCode)."
                if($result.Content -ne $null){
                    $body=$result.Content
                    #little clean up
                    if($body.IndexOf('<') -ne 0) {$body=$body.Substring($body.IndexOf('<'),$body.Length-$body.IndexOf('<'))}
                    $body = [xml] $body
                    if($body -ne $null -and $body.$rootTag){
                        $fullBody += $body.SelectNodes("//$searchTag")						    
                        switch ($rootTag) {
                            'EnumerationResults' {
                                $nextMarker = $body.EnumerationResults.NextMarker.'#text'
					            }
                        }
                    }
                    else {
                        write-warning 'Got empty response body'
                        $broken=$true
                    }
                }
            }
		    else {
			    $broken=$true
		    }
        }
        while (![String]::IsNullOrEmpty($nextMarker) -and ! $broken)

        $returnObject.StatusCode=$result.StatusCode
        $returnObject.LastContent=$body
        $returnObject.ParsedValues=$fullBody
        if($fullbody.Count -gt 0) {$returnObject.GotContent=$true}

    }
    catch {
       Write-Error ('Exception processing query {0}' -f $_.GetType().FullName)
        Write-Verbose $_
        $errornode=('<![CDATA[{0}]]>' -f [System.Web.HttpUtility]::HtmlENcode($_))
        if ($returnObject.LastContent) {
            $node=$returnObject.LastContent.CreateNode([System.Xml.XmlNodeType]::Element,'error','')
            $node.InnerXml=$errornode
            $returnObject.LastContent.LastChild.AppendChild($errornode)
        } 
        else {
            $returnObject.LastContent =[xml] ('<error>{0}</error>' -f $errornode)
        }
    }
    return $returnObject
}
