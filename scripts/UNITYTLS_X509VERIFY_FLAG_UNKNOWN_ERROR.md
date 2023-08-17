UNITYTLS_X509VERIFY_FLAG_UNKNOWN_ERROR
UNITYTLS_X509VERIFY_FLAG_NOT_TRUSTED
https://github.com/proyecto26/RestClient/issues/197
https://github.com/proyecto26/RestClient
https://community.letsencrypt.org/t/ssl-certificate-validation-in-unity/60135/7
https://discussions.unity.com/answers/1144063/view.html
https://www.google.com/search?client=firefox-b-1-e&q=UNITYTLS_X509VERIFY_FLAG_UNKNOWN_ERROR

https://www.google.com/search?client=firefox-b-1-e&q=unity+CERT_UNKNOWN


#!/usr/bin/env pwsh
<#
Anti idle logoff for jorbz of the scheduled variety
Useful references:
    1. [WQL syntax reference](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wql-sql-for-wmi)
    2. [filtering WMI by more than one property](https://stackoverflow.com/questions/7512734/powershell-filtering-wmiobject-processes-by-more-than-one-name)
    3. [Initial SO article for getting cmdline since get-process didn't have it](https://stackoverflow.com/questions/17563411/how-to-get-command-line-info-for-a-process-in-powershell-or-c-sharp)


#>

#Get-Process -Name "powershell"
#(Get-CimInstance Win32_Process -Filter "name = 'powershell.exe' AND CommandLine = 'powershell  -Ex Bypass'").CommandLine
#$idleLogoffSCriptProcess = (Get-CimInstance Win32_Process -Filter "name = 'powershell.exe' AND CommandLine LIKE '%-windowStyle hidden -NoProfile -ExecutionPolicy Bypass -file C:\\WINDOWS\\System32\\idleLogoff\\idle.ps1%'").ProcessId
$idleLogoffScriptProcess = (Get-CimInstance Win32_Process -Filter "name = 'powershell.exe' AND CommandLine LIKE '%idleLogoff\\idle.ps1%'")
Stop-Process -Id $idleLogoffScriptProcess.ProcessId -Confirm

# https://superuser.com/questions/1373275/how-to-schedule-a-task-with-powershell-to-run-every-hour-monday-to-friday-betwe

$task = Get-ScheduledTask -TaskName "Operative Anti-Idle Logoff Task" 2> $null > $null

if ($null -eq $task) {
    #make new task.
    New-ScheduledTask .\AIdleLogoff.ps1
}



