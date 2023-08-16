#!/usr/bin/env pwsh
<#
Module defines PowerShell classes and methods for executing multithreaded code in a runspace pool.
aka
PowerShell THREADS REEEEEEEEEEEEEEEEEEEEEEEEEE!

Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230727
Last Mod: 3 Aug 2023

LICENSE: AGPLv3 you MUST release all source code using this for all the things including server side only stuff!

AGPL-3.0-or-later

LICENSE: https://www.gnu.org/licenses/agpl-3.0.en.html
LICENSE: https://choosealicense.com/licenses/agpl-3.0/
LICENSE: https://tldrlegal.com/license/gnu-affero-general-public-license-v3-(agpl-3.0)
LICENSE HEADER:
    This file is part of <project>.

    <project> is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    <project> is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with <project>.  If not, see <https://www.gnu.org/licenses/>.


#>

using namespace System.Management.Automation
using namespace System.Management.Automation.Runspaces

<#
.SYNOPSIS
    Represents a PowerShell thread that can execute a scriptblock in the background.
    Gumby = flexible, can be used for many things, and can be bent to your will.

.DESCRIPTION
    The GumbyThread class provides a simple way to create and manage PowerShell Runspace based threads that execute a scriptblock in the background.
    The class encapsulates a PowerShell instance, thread handle, and a scriptblock, the thread is started on instantiation.
    Provides a method to "join" the thread like in the pthreads (posix threads) library.

.NOTES
    Author: @OperativeThunny ( bluesky @verboten.zip )
    Date: 20230727
    Last Mod: 1 Aug 2023
    License: AGPLv3 you MUST release all source code using this for all the things including server side only stuff!

.EXAMPLE
    # Create a GumbyThread instance and start the thread
    using namespace System.Management.Automation
    using namespace System.Management.Automation.Runspaces
    $GumbyPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 5)
    $GumbyPool.Open()
    $GumbyBody = { param($GumbyParam) Write-Output "Hello from thread $([System.Threading.Thread]::CurrentThread.ManagedThreadId) with param $GumbyParam"; ForEach ($i in 1..10) { Start-Sleep -Seconds 1; Write-Output "Work unit $($i) executed!" } }
    $GumbyParams = "Gumby33333"
    $GumbyThread = [GumbyThread]::new($GumbyPool, $GumbyBody, $GumbyParams)
    $GumbyThread.Join()
    $GumbyThread.Dispose()


.LINK
    https://xkln.net/blog/multithreading-in-PowerShell--running-a-specific-number-of-threads/
    https://devblogs.microsoft.com/scripting/beginning-use-of-powershell-runspaces-part-3/

#>
function Test-GumbyThread() {
    $GumbyPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 5)
    $GumbyPool.Open()
    $GumbyBody = { param($GumbyParam) Write-Output "Hello from thread $([System.Threading.Thread]::CurrentThread.ManagedThreadId) with param $GumbyParam"; ForEach ($i in 1..10) { Start-Sleep -Seconds 1; Write-Output "Work unit $($i) executed!" } }
    $GumbyParams = "Gumby33333"
    $GumbyThread = [GumbyThread]::new($GumbyPool, $GumbyBody, $GumbyParams)
    $GumbyThread.Join()
    $GumbyThread.Dispose()
}

class GumbyThread : System.IDisposable {
    [System.IAsyncResult] $GumbyThreadHandle # Actual type is internal sealed class [System.Management.Automation.PowerShellAsyncResult]
    [System.Management.Automation.PowerShell] $PSInstanceInvoker
    hidden [scriptblock] $ThreadCode
    hidden [bool] $IsDisposed = $false

    hidden [void] Init([PowerShell]$ThreadInstance, [scriptblock]$GumbyBody, [object]$GumbyParams = $null) {
        $this.IsDisposed = $false
        $this.ThreadCode = $GumbyBody
        $this.PSInstanceInvoker = $ThreadInstance
        $this.PSInstanceInvoker.AddScript($this.ThreadCode)
        if ($null -ne $GumbyParams) {
            if ($GumbyParams -is [System.Collections.IList] -or $GumbyParams -is [System.Collections.IDictionary]) {
                $this.PSInstanceInvoker.AddParameters($GumbyParams)
            } else {
                $this.PSInstanceInvoker.AddArgument($GumbyParams)
            }
        }
        $this.GumbyThreadHandle = $this.PSInstanceInvoker.BeginInvoke()
    }

    GumbyThread([RunspacePool]$rsp, [scriptblock]$ThreadCode, [object]$ThreadParams = $null) {
        [PowerShell]$this.PSInstanceInvoker = [PowerShell]::Create()
        $this.PSInstanceInvoker.RunspacePool = $rsp

        $this.Init($this.PSInstanceInvoker, $ThreadCode, $ThreadParams)
    }

    <#
    .SYNOPSIS
        Wait! for the thread to complete and return the results.
    #>
    [System.Management.Automation.PSDataCollection[psobject]] Join() {
        return $this.Join($true)
    }

    <#
    .SYNOPSIS
        Wait? for the thread to complete and return the results.
    #>
    [System.Management.Automation.PSDataCollection[psobject]] Join($wait = $true) {
        while ($wait -and !($this.GumbyThreadHandle.IsCompleted)) {
            # show all streams:
            # $this.PSInstanceInvoker.Streams.Error
            # $this.PSInstanceInvoker.Streams.Warning
            # $this.PSInstanceInvoker.Streams.Verbose
            # $this.PSInstanceInvoker.Streams.Debug
            # $this.PSInstanceInvoker.Streams.Information
            # $this.PSInstanceInvoker.Streams.Progress
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Error | ForEach-Object { Write-Error $_ }
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Warning | ForEach-Object { Write-Warning $_ }
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Verbose | ForEach-Object { Write-Verbose $_ }
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Debug | ForEach-Object { Write-Debug $_ }
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Information | ForEach-Object { Write-Information $_ }
            # ([PowerShell]($this.PSInstanceInvoker)).Streams.Progress | ForEach-Object { Write-Progress $_ }

            Start-Sleep -Milliseconds 20
        }

        if ($this.GumbyThreadHandle.IsCompleted) {
            #System.Management.Automation.PSDataCollection`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]
            [System.Management.Automation.PSDataCollection[PSObject]]$threadResult = $this.PSInstanceInvoker.EndInvoke($this.GumbyThreadHandle)
            $threadResult.GetType()
            $threadResult.GetType().FullName
            $this.Dispose()
            return $threadResult
        }

        return $null # Maybe return PSDataCollection[psobject]?
        # TODO: Strictly require pthreads behavior of blocking until done, or no?
    }

    [bool] CanDispose() {
        return !($this.IsDisposed)
    }

    [void] Dispose() {
        if (!($this.IsDisposed) -and $null -ne $this.PSInstanceInvoker) {
            [void] $this.PSInstanceInvoker.Dispose() # casting to void is equivalent of 2>&1 > $null, | Out-Null, or > $null
        }
        $this.IsDisposed = $true
        $this.PSInstanceInvoker = $null
        $this.GumbyThreadHandle = $null
        $this.ThreadCode = $null

    }
}

<#
Thread manager - pass it code and tell it to start threads and then collect results.
#>
class GumbyThreadJeffe : System.IDisposable {
    [GumbyThread[]]$GumbyThreads = [GumbyThread[]]@()
    hidden [System.Management.Automation.ScriptBlock]$GumbyBody
    [System.Management.Automation.Runspaces.RunspacePool]$GumbyPool
    [System.Management.Automation.Runspaces.InitialSessionState]$GumbySessionState
    hidden [System.Double]$CleanupInterval

    # PowerShell doesn't have syntax for constructor chaining :(
    hidden [void] Init([scriptblock]$codeToExecuteForElJeffe, [UInt32]$MaxThreads, [double]$CleanupInterval, [initialsessionstate]$initState, [Host.PSHost]$gumbyhost = $host) {
        [RunspacePool]$this.GumbyPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
            1,
            $MaxThreads,
            $initState,
            $gumbyhost
        )
        $this.GumbyBody = $codeToExecuteForElJeffe
        $this.GumbyPool.CleanupInterval = [System.TimeSpan]::FromSeconds($CleanupInterval)
        $this.GumbyPool.Open()
    }

    GumbyThreadJeffe ([scriptblock]$ThreadBody, [Host.PSHost]$gumbyhost = $host) {
        #$rsp.CleanupInterval = [System.TimeSpan]::FromSeconds([double]5.7) # 5/7 iykyk ;) (0.7142857142857143... but meh close enough)
        $this.Init(
            $ThreadBody,
            69,
            ([double](([double]5.0/[double]7.0)*[double]10.0)),
            [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault(),
            $gumbyhost
        )
    }

    GumbyThreadJeffe([scriptblock]$ThreadBody, [UInt32]$MaxThreads, [double]$CleanupInterval, [initialsessionstate]$initState, [Host.PSHost]$gumbyhost = $host) {
        $this.Init(
            $ThreadBody,
            $MaxThreads,
            $CleanupInterval,
            $initState,
            $gumbyhost
        )
    }

    # [void] AddThread([scriptblock]$ThreadCode, [object]$ThreadParams = $null) {
    #     $this.GumbyThreads += [GumbyThread]::new($this.GumbyPool, $ThreadCode, $ThreadParams)
    # }

    <#
    .SYNOPSIS
        Execute a new thread with the given code and arguments.
        TODO and return a handle to the thread?
    #>
    [void] GumbySplit($ThreadArguments) {
        $t = [GumbyThread]::new($this.GumbyPool, $this.GumbyBody, $ThreadArguments)
        $this.GumbyThreads += $t
        #Write-Output "Threads left: $($this.GumbyPool.GetAvailableRunspaces())"
    }

    [PSDataCollection[psobject][]] GumbyMerge() {
        return $this.GumbyMerge($false)
    }

    <#
    .SYNOPSIS
        Wait?? for all threads to complete and return the results.
    #>
    [PSDataCollection[psobject][]] GumbyMerge($wait = $false) {
        # this **might** be faster than foreach beacuse foreach grabs an enumerator??
        $len = $this.GumbyThreads.Length
        $dirty = $false
        [PSDataCollection[psobject][]]$GumbyResults = [PSDataCollection[psobject][]]@()
        for ($i = 0; $i -lt $len; $i++) {
            [GumbyThread]$thread = $this.GumbyThreads[$i]

            if ($null -eq $thread) {
                $dirty = $true
                continue
            }

            if ($wait) { # TODO: clean this up its messy. dont dive into the implementation details of gumbythread, use the gumbythread methods.
                $GumbyResults += $thread.Join($true)
                $thread.Dispose()
                $this.GumbyThreads[$i] = $null
                $dirty = $true
            } else {
                if ($thread.GumbyThreadHandle.IsCompleted) {
                    $GumbyResults += ([PSDataCollection[psobject]](([PowerShell]($thread.PSInstanceInvoker)).EndInvoke($thread.GumbyThreadHandle)))
                    [void] ([PowerShell]($thread.PSInstanceInvoker)).Dispose()
                    $this.GumbyThreads[$i] = $null
                    $dirty = $true
                }
            }
        }

        if ($dirty) {
            $this.GumbyThreads = $this.GumbyThreads | Where-Object { $null -ne $_ }
        }

        return [PSDataCollection[psobject]]$GumbyResults
    }

    <#
    .SYNOPSIS
        Get all the streams from all the threads.
    #>
    [PSDataCollection[psobject]] GumbyStreams() {
        $len = $this.GumbyThreads.Length
        [PSDataCollection[psobject]]$GumbyStreams = [PSDataCollection[psobject]]@()
        for ($i=0; $i -lt $len; $i++) {
            [GumbyThread]$thread = $this.GumbyThreads[$i]
            if ($null -eq $thread) {
                continue
            }
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Error
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Warning
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Verbose
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Debug
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Information
            # $GumbyStreams += ([PowerShell]($thread.PSInstanceInvoker)).Streams.Progress
            $streamz = @{
                ThreadID = $thread.GumbyThreadHandle.AsyncState.ManagedThreadId
                Debug = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Debug
                Error = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Error
                Information = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Information
                Progress = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Progress
                Verbose = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Verbose
                Warning = ([PowerShell]($thread.PSInstanceInvoker)).Streams.Warning
            }
            $GumbyStreams += $streamz
        }

        return [PSDataCollection[psobject]] $GumbyStreams
    }

    <#
    .SYNOPSIS
        Smashes the class instance, killing all threads, and returns the results.
        Wait for all threads to complete and return the results.
        HULK_SMASH for killing all threads, terminate all threads forcefully, first closing completed threads.
    #>
    [PSDataCollection[psobject][]] HULK_SMASH() {
        [PSDataCollection[psobject][]]$AngryResults = $this.GumbyMerge($false)

        $len = $this.GumbyThreads.Length

        for ($i = 0; $i -lt $len; $i++) {
            $this.GumbyThreads[$i].Dispose()
            #$this.GumbyThreads[$i].PSInstanceInvoker.Dispose()
            $this.GumbyThreads[$i] = $null
        }

        $this.GumbyThreads = $this.GumbyThreads | Where-Object { $null -ne $_ }

        [GC]::Collect()

        return $AngryResults
    }

    [void] Dispose() {
        $this.HULK_SMASH()
        ([System.Management.Automation.Runspaces.RunspacePool]$this.GumbyPool).Dispose()
    }
}

# class GumbyThreadRunner : System.IDisposable {
#     <# Define the class. Try constructors, properties, or methods. #>
#     GumbyThreadRunner() {
#         <# Initialize the class. Use $this to reference the properties of the instance you are creating #>
#     }
# }

Export-ModuleMember -Function * -Cmdlet * -Alias * -Variable *

