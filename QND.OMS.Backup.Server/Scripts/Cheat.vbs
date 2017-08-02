
'ok this is a really silly way to discover the server let's change it in the next release
SetLocale("en-us")
Set oAPI = CreateObject("MOM.ScriptAPI") 
Set oArgs = WScript.Arguments 

call oAPI.LogScriptEvent("DPMServerDiscovery", 125, 4, "OMS AzBksSrvr Cheat server discovery start event")

if oArgs.Count < 7 Then 
    call oAPI.LogScriptEvent("DPMServerDiscovery", 12, 1, "Expected 7 arguments. There were only " & oArgs.Count & " arguments. Exiting script.")
	Wscript.Quit -1
End If 

SourceType = oArgs(0)
SourceId = oArgs(1)
ManagedEntityId = oArgs(2)
TargetComputer = oArgs(3)
NetbiosComputerName = oArgs(4)
NetbiosDomainName = oArgs(5)
ManagementGroupName = oArgs(6)

Dim dpmProductCode, installstate, dpmversion

Const msiInstallStateUnknown = -1
Const msiInstallStateAbsent	 = 2

isDPMPresent = True

Set oDiscData = oAPI.CreateDiscoveryData(SourceType, SourceId, ManagedEntityId)

'this discovery method is silly, anyway stick to the original MP
dpmProductCode = "{54CF55F6-45E0-494E-94E4-6D9AA80663B0}" 'Azure Backup Server v1 = DPM2012R2
    
installstate = MsiQueryProductState(dpmProductCode)

if installstate = msiInstallStateUnknown or installState = msiInstallStateAbsent then
      dpmProductCode = "{967E1926-C053-41E8-AF10-0E0061A9E00F}"
      installstate = MsiQueryProductState(dpmProductCode)
End if


If installstate = msiInstallStateUnknown or installState = msiInstallStateAbsent then
      call oAPI.LogScriptEvent("DPMServerDiscovery", 125, 1, "OMS AzBksSrvr Cheat Server is not present on this computer")
	  isDPMPresent = False
else
      'MsgBox("DPM is Present")

      dpmversion = MsiGetProductInfo(dpmProductCode)

      Set oInst = oDiscData.CreateClassInstance("$MPElement[Name="DPM!Microsoft.SystemCenter.DataProtectionManager.2011.Library.DPMServer"]$")
        
      call oInst.AddProperty("$MPElement[Name="Windows!Microsoft.Windows.Computer"]/PrincipalName$", TargetComputer)
      call oInst.AddProperty("$MPElement[Name="DPM!Microsoft.SystemCenter.DataProtectionManager.2011.Library.DPMSeed"]/DPMServerName$", TargetComputer)
      call oInst.AddProperty("$MPElement[Name="System!System.Entity"]/DisplayName$",NetbiosComputerName)
      call oInst.AddProperty("$MPElement[Name="DPM!Microsoft.SystemCenter.DataProtectionManager.2011.Library.DPMServer"]/DPMServerName$", TargetComputer)
      call oInst.AddProperty("$MPElement[Name="DPM!Microsoft.SystemCenter.DataProtectionManager.2011.Library.DPMServer"]/Domain$", NetbiosDomainName)

      call oDiscData.AddInstance(oInst)
End if 

call oAPI.LogScriptEvent("DPMServerDiscovery", 125, 4, "OMS AzBksSrvr Cheat server discovery SCOM ManagementGroup:" & ManagementGroupName)

AddSCOMServerToDPMSCOMGroup(ManagementGroupName)

if (isDPMPresent) then
	CheckForScriptLimitRegistry()
end if

call oAPI.LogScriptEvent("DPMServerDiscovery", 125, 4, "OMS AzBksSrvr Cheat server discovery completed event")

call oAPI.Return(oDiscData)

Function MsiQueryProductState(ProductCode)
    Dim InstallState
	
    Dim Installer : Set Installer = Nothing
    Set Installer = CreateObject("WindowsInstaller.Installer")
    InstallState = Installer.ProductState(ProductCode)

    MsiQueryProductState = InstallState
	
    Exit Function
End Function

Function MsiGetProductInfo(ProductCode)
   Dim InstallInfo
   Dim Installer : Set Installer = Nothing
   Set Installer = CreateObject("WindowsInstaller.Installer")
   InstallInfo = Installer.ProductInfo(ProductCode,"VersionString")

   MsiGetProductInfo = InstallInfo
End Function

Function AddSCOMServerToDPMSCOMGroup(managementGroupName)

  'This is required as discovery should not stop because of err in this script
  on error resume next

  Const HKEY_LOCAL_MACHINE  = &H80000002
  Const REG_SZ = 1
  strComputer = "."
  hDefKey = HKEY_LOCAL_MACHINE
  strKeyPath = "SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups\" & managementGroupName & "\Parent Health Services\0"
  dpmConfigKeyPath = "SOFTWARE\Microsoft\Microsoft Data Protection Manager\Configuration"
  strValueName = "NetworkName"
  DPMScomGroupName = "DPMScom"
  
  'Reading Registry
  Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\default:StdRegProv")
  oReg.GetExpandedStringValue hDefKey, strKeyPath, strValueName, scomSvrName

  'Adding To DPMScom Group Variables
  'Seperating Machine name and domain name
  DotPosition = InStr (scomSvrName, ".")
  DomainName = Mid (scomSvrName, DotPosition+1)
  DotPosition2 = InStr (DomainName, ".")
  simpleDomainName = Mid (DomainName, 1, DotPosition2 - 1)
  MachineName = Mid (scomSvrName, 1, DotPosition-1) & "$"
  Set net = WScript.CreateObject("WScript.Network")
  local = net.ComputerName

  'Read Machine Name
  Set WshShell = WScript.CreateObject("WScript.Shell")
  DPMMachineName = WshShell.ExpandEnvironmentStrings("%COMPUTERNAME%")
  DPMScomGroupNameDCMachineName = "DPMScom$" & DPMMachineName

  'Adding SCOMServer to DPMSCOM Group for non-dc machine
  set group = GetObject("WinNT://"& local &"/" & DPMScomGroupName)
  group.Add "WinNT://"& DomainName &"/"& MachineName &""

  'Adding SCOMServer to DPMSCOM Group for dc machine
  set group = GetObject("WinNT://"& local &"/DPMScomGroupNameDCMachineName")
  group.Add "WinNT://"& DomainName &"/"& MachineName &""

  'Adding registry for the scomserver so indicate when discovery happened subKeyName = "domain\serverName$" value = "Just Discovered"
  valueTemp = "Just Discovered"
  subKeyValue = simpleDomainName & "\" & MachineName
  oReg.SetStringValue HKEY_LOCAL_MACHINE, dpmConfigKeyPath, subKeyValue, valueTemp 

End Function

Function CheckForScriptLimitRegistry()

  'This is required as discovery should not stop because of err in this script
  on error resume next

  Dim objShell
  Set objShell=CreateObject("WScript.Shell")

  scriptString = "$regPath = 'HKLM:\Software\Microsoft\Microsoft Operations Manager\3.0\Modules\Global\Powershell'  "&_
  Chr(10) &      "$setRegistry = $false  "&_
  Chr(10) &      "if(Test-Path $regPath)  "&_
  Chr(10) &      "{  "&_
  Chr(10) &      "    write-host ""Key exists""  "&_
  Chr(10) &      "    $value = Get-ItemProperty -Name ""ScriptLimit"" -Path $regPath -ErrorAction silentlycontinue  "&_
  Chr(10) &      "    if($value -eq $null)  "&_
  Chr(10) &      "    {  "&_
  Chr(10) &      "        New-ItemProperty $regPath -Name ""ScriptLimit"" -Value 15 -PropertyType DWORD  "&_
  Chr(10) &      "        $setRegistry = $true    "&_
  Chr(10) &      "    }  "&_
  Chr(10) &      "    elseif($value.ScriptLimit -gt 15)  "&_
  Chr(10) &      "    {  "&_
  Chr(10) &      "        write-host ""Value is null or value is greater than 15""   "&_
  Chr(10) &      "        Set-ItemProperty -path $regPath -Name ""ScriptLimit"" -Value 15  "&_
  Chr(10) &      "        $setRegistry = $true    "&_
  Chr(10) &      "    } "&_
  Chr(10) &      "}     "&_
  Chr(10) &      "else  "&_
  Chr(10) &      "{     "&_
  Chr(10) &      "    write-host ""Key doesnt exist""   "&_
  Chr(10) &      "    md $regPath  "&_
  Chr(10) &      "    New-ItemProperty $regPath -Name ""ScriptLimit"" -Value 15 -PropertyType DWORD  "&_
  Chr(10) &      "    $setRegistry = $true  "&_
  Chr(10) &      "}   "&_
  Chr(10) &      "if($setRegistry)  "&_
  Chr(10) &      "{  "&_
  Chr(10) &      "    $evt = new-object System.Diagnostics.EventLog('DPM Alerts');  "&_
  Chr(10) &      "    $evt.Source = 'DPM-EM';  "&_
  Chr(10) &      "    $eventSeverity = [System.Diagnostics.EventLogEntryType]::Information;  "&_
  Chr(10) &      "    $eventString = 'Restarting the health service';  "&_
  Chr(10) &      "    $eventId = 126;  "&_
  Chr(10) &      "    $evt.WriteEntry($eventString, $eventSeverity, $eventId)  "&_
  Chr(10) &      "    $time= (Get-Date).AddMinutes(10)   "&_
  Chr(10) &      "    $timeStr = $time.ToString('HH:mm')   "&_
  Chr(10) &      "    $result = schtasks /create /tn DPMDiscoveryHelper /tr 'net start healthservice' /st $timeStr /rl highest /sc once /ru system /rp /f  "&_
  Chr(10) &      "    if($LASTEXITCODE -eq 0)  "&_
  Chr(10) &      "    {  "&_
  Chr(10) &      "       $eventString = 'Successfully created the scheduled task';  "&_
  Chr(10) &      "    } "&_
  Chr(10) &      "    else "&_
  Chr(10) &      "    {  "&_
  Chr(10) &      "       $eventString = 'Failed creating scheduled task with message' + $result;  "&_
  Chr(10) &      "    } "&_
  Chr(10) &      "    $evt.WriteEntry($eventString, $eventSeverity, $eventId)  "&_
  Chr(10) &      "    Stop-Service healthservice   "&_
  Chr(10) &      "    Start-Service healthservice  "&_
  Chr(10) &      "}"

  strCMD="powershell -nologo -command """ & scriptString & """"

  'Uncomment next line for debugging
  'MsgBox("strCMD: " & strCMD)

  'use 0 to hide window
  objShell.Run strCMD,0,true

End Function
