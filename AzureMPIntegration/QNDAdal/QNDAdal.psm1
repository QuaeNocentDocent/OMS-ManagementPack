
param(
    [bool] $install=$true,
    [string] $requiredVersion='2.14.0.0',
    [bool] $latest=$true,
    [string[]] $searchPath
)

function Install-ActiveDirectoryAuthenticationLibrary
{
param(
    [bool] $install=$true,
    [string] $requiredVersion='2.14.0.0',
    [bool] $latest=$true
)

    $searchDirs=@("$PSScriptRoot","$((Get-Module QNDAdal).ModuleBase)")
    $SCOMResPath = (get-itemproperty -path 'HKLM:\system\currentcontrolset\services\healthservice\Parameters' -Name 'State Directory' -ErrorAction SilentlyContinue).'State Directory' + '\Resources'
    if ($SCOMResPath) {$searchDirs+=$SCOMResPath}
    if ($searchPath) {$searchDirs+=$searchPath}

    $adal=[AppDomain]::CurrentDomain.GetAssemblies() |Where-Object { $_.FullName -match "Microsoft.IdentityModel.Clients.ActiveDirectory, Version=(.*), Culture=neutral, PublicKeyToken=31bf3856ad364e35"}
    if ($adal) {
        $adalVersion= $Matches[1]
        if ($adalVersion -lt $requiredVersion) {$adal=$null}
    }
    If (!($adal))
    {
	    Write-verbose 'Microsoft.IdentityModel.Clients.ActiveDirectory not loaded...'
	    Try {
            foreach ($dir in $searchDirs) {
				write-verbose ('Seraching in {0}' -f $dir)
                $adalPackage = @(Get-ChildItem -Path ($dir) -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory.dll" -Recurse)[0]
				$adalWindowsForms = @(Get-ChildItem -Path ($dir) -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll" -Recurse)[0] #this one is optional used only for UI
                if ($adalPackage) {
				#$adalPackage
					write-verbose ('Found in {0}' -f $dir)
                    break
                }
            }
            if (! ($adalPackage) -and $install) {
                #check if we can write in the module directory
                try {
                    New-Item (Join-Path $PSScriptRoot 'check.me') -Force
                    $workingDir = $PSScriptRoot
                }
                catch {
                    write-verbose "Cannot create files in $PSScriptRoot"
                    $workingDir = [System.IO.Path]::GetTempPath()
                }
                $nugetFolder = (join-path $workingDir "Nugets")
                if(-not (Test-Path $nugetFolder)) {New-Item -Path $nugetFolder -ItemType "Directory" | out-null}
                if(-not(Test-Path (join-path $nugetFolder 'nuget.exe'))) {
                  Write-Verbose "nuget.exe not found. Downloading from http://www.nuget.org/nuget.exe ..."
                  $wc = New-Object System.Net.WebClient
                  $wc.DownloadFile("http://www.nuget.org/nuget.exe",(join-path $nugetFolder 'nuget.exe'));
                }
                $result = invoke-expression ((join-Path $nugetFolder 'nuget.exe') + ' list Microsoft.IdentityModel.Clients.ActiveDirectory') | where {$_ -match 'Microsoft.IdentityModel.Clients.ActiveDirectory'}
                write-verbose "About to download $result"
                if ($latest -or ([String]::IsNullOrEmpty($requiredVersion))) {
                    $version = $result.Replace('Microsoft.IdentityModel.Clients.ActiveDirectory ','')
                }
                else {
                    $version = $requiredVersion
                }               
                $nugetDownloadExpression = (join-Path $nugetFolder 'nuget.exe') + " install Microsoft.IdentityModel.Clients.ActiveDirectory -Version $version -NonInteractive -OutputDirectory " + $workingDir + "\Nugets | out-null"
                Invoke-Expression $nugetDownloadExpression
                $adalPackage = @(Get-ChildItem -Path ($workingDir) -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory.dll" -Recurse)[0]
				$adalWindowsForms = @(Get-ChildItem -Path ($workingDir) -Filter "Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll" -Recurse)[0] #this one is optional used only for UI

            }
            if ($adalPackage) {
                Add-Type -path $adalPackage.FullName | out-Null
				if ($adalWindowsForms) {
					Add-Type -path $adalWindowsForms.FullName | out-Null				
				}
				else {
					Write-Warning 'Could not load ADAL Windows Form Assembly, won''t be able to show logon UI'
				}
            }
            else {
                Throw 'Could not load ADAL'
            }
        }
        Catch {
            Write-Verbose $_
            Throw "Unable to load $($adalPackage.FullName). Please verify if the DLLs exist in this location!"
        }
    }
}

function Get-AdalAuthentication {
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string] $resourceURI,
    [Parameter(Mandatory=$true)]
    [string] $authority, 
    [string] $clientId = "1950a258-227b-4e31-a9cf-717495945fc2", # Set well-known client ID for Azure PowerShell
    [string] $redirectUri = "urn:ietf:wg:oauth:2.0:oob", # Set redirect URI for Azure PowerShell   
    [pscredential] $credential=$null
)
 
  #$resourceClientId = "00000002-0000-0000-c000-000000000000"
  #$resourceAppIdURI = $resourceURI #v1.0/ "https://graph.windows.net/"
  #$authority += "https://login.windows.net/" + $tenant

  $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority #,$false
  if ($credential) {
    if($credential.UserName -eq $clientId) { #Service Principal
        $clientCredential = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential" -ArgumentList $clientId, $credential.Password
        $authResult = $authContext.AcquireToken($resourceURI,$clientCredential)
    }
    else {
  	    $AADcredential = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential" -ArgumentList $credential.UserName,$credential.Password
        $authResult = $authContext.AcquireToken($resourceURI,$clientId,$AADcredential)
    }
  }
  else {
    $authResult = $authContext.AcquireToken($resourceURI, $clientId, $redirectUri, [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always)
  }
  return $authResult
}


Install-ActiveDirectoryAuthenticationLibrary -install $install -requiredVersion $requiredVersion -latest $latest