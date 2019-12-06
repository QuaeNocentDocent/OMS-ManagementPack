
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
            else {$result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing -Proxy $proxy -ErrorAction SilentlyContinue}
        }
        else {
            $result = Invoke-WebRequest -Method $HTTPVerb -Uri $restUri -Headers $headers -Body $body -TimeoutSec $timeoutSeconds -UseBasicParsing -ErrorAction SilentlyContinue
        }
        write-verbose ($result)
        $statusCode=$result.StatusCode
        $lastContent=$result.Content
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
					}
					$gotValue=$true
                }
            }
        }
		else {
			$returnValues=$result.Content
			$nl=$null
		}
        $StatusCode=$result.StatusCode
    }
    catch {	
        $message= ('Exception processing query {0} Type: {1}' -f $_.ErrorDetails.Message, $_.GetType().FullName)
        Write-Error $message
        Write-Verbose $_
        $nl=$null
        if ($result) {$StatusCode=$result.StatusCode;$lastContent=$result}
        else {
            $StatusCode=500
            [array]$returnValues = $_.ErrorDetails
			$lastContent=$_.ErrorDetails.Message
        }
    }
	finally {
      $returnObject = new-object -TypeName PSCustomObject -Property @{
        'Values' = $returnValues
        'NextLink' = $nl
        'StatusCode' = $StatusCode
		'GotValue' = $gotValue
        'lastContent' = $lastContent
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


Function Get-QNDOMSQueryResult
{
[CmdletBinding()]
param(
[string] $query,
[datetime] $startDate,
[datetime] $endDate,
[int] $timeout,
[string] $authToken,
[string]$ResourceBaseAddress,
[string]$resourceURI,
[string]$OMSAPIVersion,
[int] $delay=1,
[int] $top=99999
)
	try {
        $QueryArray = @{Top=$top}
		$QueryArray+= @{query=$Query}
		$QueryArray+= @{start=('{0}Z' -f $startDate.GetDateTimeFormats('s'))}
		$QueryArray+= @{end=('{0}Z' -f $endDate.GetDateTimeFormats('s'))}
		$body = ConvertTo-Json -InputObject $QueryArray

		$uri = '{0}{1}/search?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion
		$nextLink=$null
		$results=@()
		do {
            do {
			    $result = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken $authToken -nextLink $nextLink -data $body -TimeoutSeconds $timeout
                $lastResult=(ConvertFrom-Json $result.LastContent)
                write-verbose $lastResult.__metadata
                $pending=$false
                if ($lastResult.__metadata.Status -ieq 'Pending') {
                    $uri=('{0}{1}?api-version={2}' -f $ResourceBaseAddress, $lastResult.Id, $OMSAPIVersion)
                    $pending=$true
                    write-verbose 'Qeury still pedning, waiting'
                    start-sleep -Seconds $delay
                }

            } while ($pending)

			$nextLink = $result.NextLink
            if($result.GotValue) {$results += $result.values}
		} while ($nextLink)
#we need to check for an empty result, the behavior has changed and in this case it returns a pending status
        try {
            if ($results.count -eq 1) {
                if($results.__metadata.NumberOfDocuments -eq 0) {$results=@()}
            }

        }
        catch {
			Log-Event $EVENT_ID_FAILURE $EVENT_TYPE_WARNING ('Unexpected error checking for query results {0} on uri {1}. {2}' -f $Error[0], $query, $uri) $TRACE_WARNING
            $results=@()
        }
		return ([array] $results)
	}
	catch {
			Log-Event $EVENT_ID_FAILURE $EVENT_TYPE_ERROR ("Error querying OMS {0} for query {1} and uri {2}" -f $Error[0], $query, $uri) $TRACE_ERROR
	}
}

Function Get-QNDKustoQueryResult
{
	[CmdletBinding()]
	param(
	[string] $query,
	[string] $timespan,
	[int] $timeout,
	[string] $authToken,
	[string]$ResourceBaseAddress,
	[string]$resourceURI,
	[string]$OMSAPIVersion
	)
	try {

		$uri = '{0}{1}/api/query?api-version={2}' -f $ResourceBaseAddress,$resourceURI,$OMSAPIVersion	
		$body='{{"query": "{0}", "timespan":"{1}"}}' -f $query, $timespan
		$header=@{
			"Prefer"="response-v1=true;wait=$timeout"
			"Content-Type"="application/json"
			}

		$nextLink=$null
		$items=@()
		do {
			$result = invoke-QNDAzureRestRequest -uri $uri -httpVerb POST -authToken $authToken -nextLink $nextLink -data $body -TimeoutSeconds 300 -otherHeader $header
			if($result.StatusCode -notmatch '2[0-9][0-9]') {throw ($result.LastContent)}
			$nextLink = $result.NextLink
			if($result.Values) {
				$table=$result.Values.tables[0]
				foreach($row in $table.rows) {
					$column=0
					$item=@{}
					foreach($key in $table.columns) {
						$item.Add($key.Name,$row[$column] -as $key.Type)
						$column++        
					}
					$items+=New-Object -TypeName PSCustomObject -Property $item
				}
			}
		} while ($nextLink)
		return $items
	}
	catch {
			throw ("Error querying OMS {0} for query {1} and uri {2}" -f $Error[0], $query, $uri)
	}
}