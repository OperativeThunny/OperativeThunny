#!/usr/bin/env pwsh
<#
Back up Windows user settings prior to a computer replacement!
This does **NOT** back up the user's files, only the settings. Back up your user directory separately.

Author: @OperativeThunny
Date: 10 August 2023
Last mod: 14 August 2023

Copyright (C) 2023 @OperativeThunny. All rights reserved. Do not use, modify, copy, and/or distribute.
Reference links:
    https://jdhitsolutions.com/blog/powershell/8420/managing-the-windows-10-taskbar-with-powershell/
        https://www.howtogeek.com/677619/how-to-hide-the-taskbar-on-windows-10/
    https://stackoverflow.com/questions/4491999/configure-windows-explorer-folder-options-through-powershell/4493994#4493994
    https://www.addictivetips.com/windows-tips/how-back-up-the-taskbar-layout-windows-10/
    https://old.reddit.com/r/PowerShell/comments/ylsgjt/creating_and_restoring_backup_of_taskbar_in/
#       https://4sysops.com/archives/configure-pinned-programs-on-the-windows-taskbar-with-group-policy/
#>
param (
    [Parameter(Mandatory)]
    [ValidateSet("Backup", "Restore")]
    [string]$Operation            = "Backup",
    [string]$backupDirPrefix      = "CustomiziationsAndBookmarksBackup",
    [string]$backupDir            = "$($env:USERPROFILE)\OneDrive - US Army\Documents",
    [string]$backupDirUnique      = "$($backupDir)\$($backupDirPrefix)$($(Get-Date).ToFileTimeUtc())",

# account for these suffixes being hardcoded down in the restore area:
    [string]$taskbarButtonsDir    = "$($backupDirUnique)\PinnedTaskbarButtons\",
    [string]$LocalAppDataBackup   = "$($backupDirUnique)\LocalAppDataBackup",
    [string]$RoamingAppDataBackup = "$($backupDirUnique)\RoamingAppDataBackup"
<# MAKE SURE YOU ACCOUNT FOR THESE VARIABLES BEING HARDCODED BELOW IF YOU DECIDE TO CHANGE THESE PARAMETERS.
HERE ARE THE PARAMETERS COPY/PASTED FROM BELOW. MAKE SURE THEY MATCH SPECIFIED PARAMETERS IF YOU DECIDE TO CHANGE STUFF OR ELSE RESTORE WONT WORK RIGHT.
taskbarButtonsDir  = "$($restoreDir)\PinnedTaskbarButtons\"
LocalAppDataBackup = "$($restoreDir)\LocalAppDataBackup"
RoamingAppDataBackup = "$($restoreDir)\RoamingAppDataBackup"
#>
)
try{
$oldPWD = Get-Location
if ($Operation -eq "Backup") {
    if (!(Test-Path $backupDirUnique)) {
        New-Item -Path $backupDirUnique -ItemType Directory
    }
    Set-Location $backupDirUnique
    # Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ WinExplorerSettingsFull.reg} # this is a lot of settings that some of which should probably not be overwritten on a new install...
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced WinFileExplorerSettings.reg} -Verbose
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons WinDesktopIconsSettings.reg} -Verbose
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 WinTaskbarHideSettings.reg} -Verbose
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband WinExplorerTaskbarSettings.reg} -Verbose
    Invoke-Command {REG EXPORT HKCU\Software\SimonTatham PuTTYSettings.reg} -Verbose

    mkdir $taskbarButtonsDir
    Set-Location $taskbarButtonsDir
    Copy-Item -Recurse -Path "$($env:APPDATA)\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\" -Destination $taskbarButtonsDir -Verbose

    mkdir $LocalAppDataBackup
    Set-Location $LocalAppDataBackup

    # hmm it appears that the exclude does not work in this approach. Attempting something else from this stack overflow:
    # https://stackoverflow.com/questions/731752/exclude-list-in-powershell-copy-item-does-not-appear-to-be-working
    #Copy-Item -Recurse -Exclude "*cache2*" -Path "$($env:LOCALAPPDATA)\Mozilla" -Destination "$($LocalAppDataBackup)\Mozilla"
    #robocopy "$($env:LOCALAPPDATA)\Mozilla" "$($LocalAppDataBackup)\Mozilla" /S /XF *.FileExtToExclude /XD *cache*
    # But, wait! A later comment in that stackoverflow says that you just need to make sure the exclude parameter is a string array:
    [string[]]$firefoxExcludes = ([string[]]@("cache2", "*cache*", "*Cache*", "*safebrowsing*", "*.bin", "*.lz4", "*icon*", "*thumbnails*", "*.final"))
    Copy-Item -Recurse -Exclude [string[]]$firefoxExcludes -Path "$($env:LOCALAPPDATA)\Mozilla" -Destination "$($LocalAppDataBackup)\Mozilla" -ErrorAction SilentlyContinue -Verbose

    # %localappdata%\microsoft\edge\User Data\Default\Bookmarks
    Copy-Item -Path "$($env:LOCALAPPDATA)\Microsoft\Edge\User Data\Default\Bookmarks" -Destination "$($LocalAppDataBackup)\EdgeBookmarks.json" -Verbose
    Copy-Item -Path "$($env:LOCALAPPDATA)\Google\Chrome\User Data\Default\Bookmarks" -Destination "$($LocalAppDataBackup)\ChromeBookmarks.json" -Verbose

    mkdir $RoamingAppDataBackup
    Set-Location $RoamingAppDataBackup

    Copy-Item -Recurse -Path "$($env:APPDATA)\Notepad++" -Destination "$($RoamingAppDataBackup)\Notepad++" -Verbose
    Copy-Item -Recurse -Exclude $firefoxExcludes -Path "$($env:APPDATA)\Mozilla" -Destination "$($RoamingAppDataBackup)\Mozilla" -ErrorAction SilentlyContinue -Verbose

} elseif ($Operation -eq "Restore") {

    # Restore the saved settings.
    ## see if $backupDirPrefix prefixed dirs exist in current dir or $backupdir without $backupdirprefix
    ### if exists, prompt to use that one
    ### if multiple exists ask which one using a command line menu
    ### if none exist tell the user they need to specify location with $backupDirPrefix and $backupDir.
    # Restore the selected/found settings.

    $CheckDirPrefix = "$($backupDir)\$($backupDirPrefix)"
    $possibleBackups = Get-ChildItem -Recurse -Path $backupDir -Filter "$($backupDirPrefix)*"
    $restoreDir = "§"

    if(!$possibleBackups) {
        Write-Error "Unable to locate a backup directory to restore. :("
        exit -1
    }

    if ($possibleBackups.Length -eq 1) {
        Write-Output "A single backup directory was located to restore: $($possibleBackups.FullName)"
        $restoreDir = $possibleBackups.FullName
    }

    if ($possibleBackups.Length -gt 1) {
        Write-Host -BackgroundColor Gray "Multiple backup directories were found. Which one do you want to restore from?"
        $i = 0
        ForEach ($dir in $possibleBackups) {
            $i++
            Write-Host -BackgroundColor Blue -NoNewLine "$($i)) "
            Write-Host -BackgroundColor Cyan "$($dir.FullName)"
        }

        $dirtyUserInput = Read-Host -Prompt "Enter a number, 1 through $($i), -1 to exit"

        if (0 -lt $dirtyUserInput -and ($i+1) -gt $dirtyUserInput) {
            $restoreDir = $possibleBackups[$($dirtyUserInput-1)].FullName
        } elseif (-1 -eq $dirtyUserInput) {
            Write-Host -BackgroundColor DarkRed "Exiting. Thank you for following directions :)"
            exit -2
        } else {
            Write-Host -BackgroundColor Yellow "You did not follow directions and that makes me a sad panda :("
            exit -99
        }
    }

    if ($restoreDir -eq "§") {
        Write-Error "Somehow we didn't chose a directory to restore from, so we have to exit. I'm sorry."
        Write-Error "You must specify a location with $($backupDirPrefix) and $($backupDir)."
        exit -3
    }

    Write-Host -BackgroundColor Green "We are going to restore '$($restoreDir)'"
###################################################################################################
    # 99 hashtags but a semicolon aint one

    Set-Location $restoreDir
    [string]$taskbarButtonsDir  = "$($restoreDir)\PinnedTaskbarButtons\"
    [string]$LocalAppDataBackup = "$($restoreDir)\LocalAppDataBackup"
    [string]$RoamingAppDataBackup = "$($restoreDir)\RoamingAppDataBackup"
    # Invoke-Command {REG IMPORT WinExplorerSettingsFull.reg} # this is a lot of settings that some of which should probably not be overwritten on a new install...
    Invoke-Command {REG IMPORT WinFileExplorerSettings.reg} -Verbose
    Invoke-Command {REG IMPORT WinDesktopIconsSettings.reg} -Verbose
    Invoke-Command {REG IMPORT WinTaskbarHideSettings.reg} -Verbose
    Invoke-Command {REG IMPORT WinExplorerTaskbarSettings.reg} -Verbose
    Invoke-Command {REG IMPORT PuTTYSettings.reg} -Verbose

    Set-Location $taskbarButtonsDir
    Copy-Item -Recurse -Path $taskbarButtonsDir -Destination "$($env:APPDATA)\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\" -Verbose

    Set-Location $LocalAppDataBackup
    # TODO: you might need to add -force
    Copy-Item -Recurse -Path "$($LocalAppDataBackup)\Mozilla" -Destination "$($env:LOCALAPPDATA)\Mozilla" -Verbose
    # %localappdata%\microsoft\edge\User Data\Default\Bookmarks
    Copy-Item -Path "$($LocalAppDataBackup)\EdgeBookmarks.json" -Destination "$($env:LOCALAPPDATA)\Microsoft\Edge\User Data\Default\Bookmarks" -Verbose
    Copy-Item -Path "$($LocalAppDataBackup)\ChromeBookmarks.json" -Destination "$($env:LOCALAPPDATA)\Google\Chrome\User Data\Default\Bookmarks" -Verbose

    Set-Location $RoamingAppDataBackup
    Copy-Item -Recurse -Path "$($RoamingAppDataBackup)\Notepad++" -Destination "$($env:APPDATA)\Notepad++" -Verbose
    Copy-Item -Recurse -Path "$($RoamingAppDataBackup)\Mozilla" -Destination "$($env:APPDATA)\Mozilla" -Verbose
} else {
    Write-Error "Invalid operation specified, somehow. But that is not supposed to be possible to ever happen!"
}
} finally {
    Set-Location $oldPWD
}