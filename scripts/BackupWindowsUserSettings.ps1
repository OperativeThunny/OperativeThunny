#!/usr/bin/env pwsh
<#
Back up Windows user settings prior to a computer replacement!
This does **NOT** back up the user's files, only the settings. Back up your user directory separately.

Author: @OperativeThunny
Date: 10 August 2023
Last mod: 14 August 2023

Copyright (C) 2023 @OperativeThunny. All rights reserved. Do not use, modify, copy, and/or distribute.

Reference links:
    1. https://jdhitsolutions.com/blog/powershell/8420/managing-the-windows-10-taskbar-with-powershell/
        a. https://www.howtogeek.com/677619/how-to-hide-the-taskbar-on-windows-10/
    2. https://stackoverflow.com/questions/4491999/configure-windows-explorer-folder-options-through-powershell/4493994#4493994
    3. https://www.addictivetips.com/windows-tips/how-back-up-the-taskbar-layout-windows-10/
    4. https://old.reddit.com/r/PowerShell/comments/ylsgjt/creating_and_restoring_backup_of_taskbar_in/
      a. https://4sysops.com/archives/configure-pinned-programs-on-the-windows-taskbar-with-group-policy/
#>
param (
    [Parameter(Mandatory)]
    [ValidateSet("Backup", "Restore")]
    [string]$Operation            = "Backup",
    [string]$backupDirPrefix      = "CustomiziationsAndBookmarksBackup",
    [string]$backupDir            = "$($env:USERPROFILE)\OneDrive\Documents",
    [string]$backupDirUnique      = "$($backupDir)\$($backupDirPrefix)$($(Get-Date).ToFileTimeUtc())",
    [string]$taskbarButtonsDir    = "$($backupDirUnique)\PinnedTaskbarButtons\", # TODO: account for these suffixes being hardcoded down in the restore area
    [string]$LocalAppDataBackup   = "$($backupDirUnique)\LocalAppDataBackup",
    [string]$RoamingAppDataBackup = "$($backupDirUnique)\RoamingAppDataBackup"
)

if ($Operation -eq "Backup") {
    if (!(Test-Path $backupDirUnique)) {
        New-Item -Path $backupDirUnique -ItemType Directory
    }
    Set-Location $backupDirUnique
    # Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ WinExplorerSettingsFull.reg} # this is a lot of settings that some of which should probably not be overwritten on a new install...
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced WinFileExplorerSettings.reg}
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons WinDesktopIconsSettings.reg}
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 WinTaskbarHideSettings.reg}
    Invoke-Command {REG EXPORT HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband WinExplorerTaskbarSettings.reg}
    Invoke-Command {REG EXPORT HKCU\Software\SimonTatham PuTTYSettings.reg}
    mkdir $taskbarButtonsDir
    Set-Location $taskbarButtonsDir
    Copy-Item -Recurse -Path "$($env:APPDATA)\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\" -Destination $taskbarButtonsDir
    mkdir $LocalAppDataBackup
    Set-Location $LocalAppDataBackup
    Copy-Item -Recurse -Exclude "*cache2*" -Path "$($env:LOCALAPPDATA)\Mozilla" -Destination "$($LocalAppDataBackup)\Mozilla"
    # %localappdata%\microsoft\edge\User Data\Default\Bookmarks
    Copy-Item -Path "$($env:LOCALAPPDATA)\Microsoft\Edge\User Data\Default\Bookmarks" -Destination "$($LocalAppDataBackup)\EdgeBookmarks.json"
    Copy-Item -Path "$($env:LOCALAPPDATA)\Google\Chrome\User Data\Default\Bookmarks" -Destination "$($LocalAppDataBackup)\ChromeBookmarks.json"
    mkdir $RoamingAppDataBackup
    Set-Location $RoamingAppDataBackup
    Copy-Item -Recurse -Path "$($env:APPDATA)\Notepad++" -Destination "$($RoamingAppDataBackup)\Notepad++"
    Copy-Item -Recurse -Exclude "*cache2*" -Path "$($env:APPDATA)\Mozilla" -Destination "$($RoamingAppDataBackup)\Mozilla"

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
    Invoke-Command {REG IMPORT WinFileExplorerSettings.reg}
    Invoke-Command {REG IMPORT WinDesktopIconsSettings.reg}
    Invoke-Command {REG IMPORT WinTaskbarHideSettings.reg}
    Invoke-Command {REG IMPORT WinExplorerTaskbarSettings.reg}
    Invoke-Command {REG IMPORT PuTTYSettings.reg}

    Set-Location $taskbarButtonsDir
    Copy-Item -Recurse -Path $taskbarButtonsDir -Destination "$($env:APPDATA)\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\"

    Set-Location $LocalAppDataBackup
    # TODO: you might need to add -force
    Copy-Item -Recurse -Path "$($LocalAppDataBackup)\Mozilla" -Destination "$($env:LOCALAPPDATA)\Mozilla"
    # %localappdata%\microsoft\edge\User Data\Default\Bookmarks
    Copy-Item -Path "$($LocalAppDataBackup)\EdgeBookmarks.json" -Destination "$($env:LOCALAPPDATA)\Microsoft\Edge\User Data\Default\Bookmarks"
    Copy-Item -Path "$($LocalAppDataBackup)\ChromeBookmarks.json" -Destination "$($env:LOCALAPPDATA)\Google\Chrome\User Data\Default\Bookmarks"

    Set-Location $RoamingAppDataBackup
    Copy-Item -Recurse -Path "$($RoamingAppDataBackup)\Notepad++" -Destination "$($env:APPDATA)\Notepad++"
    Copy-Item -Recurse -Path "$($RoamingAppDataBackup)\Mozilla" -Destination "$($env:APPDATA)\Mozilla"
} else {
    Write-Error "Invalid operation specified, somehow. But that is not supposed to be possible to ever happen!"
}
