#!/usr/bin/env pwsh
<#
Module defines powershell classes and methods for executing multithreaded code in a runspace pool.
aka
POWERSHELL THREADS REEEEEEEEEEEEEEEEEEEEEEEEEE!

Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230727
Last Mod: 1 Aug 2023

LICENSE: AGPLv3 you MUST release all source code using this for all the things including server side only stuff!

https://xkln.net/blog/multithreading-in-powershell--running-a-specific-number-of-threads/
#>

using namespace System.Management.Automation
using namespace System.Management.Automation.Runspaces

<#

#>
class GumbyThread : System.IDisposable {
    [System.IAsyncResult] $GumbyThreadHandle # Actual type is internal sealed class [System.Management.Automation.PowershellAsyncResult]
    [System.Management.Automation.PowerShell] $PSInstanceInvoker
    [scriptblock]$ThreadCode

    hidden [void] Init([PowerShell]$ThreadInstance, [scriptblock]$GumbyBody, [object]$GumbyParams = $null) {
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
        [Powershell]$this.PSInstanceInvoker = [Powershell]::Create()
        $this.PSInstanceInvoker.RunspacePool = $rsp

        $this.Init($this.PSInstanceInvoker, $ThreadCode, $ThreadParams)
    }

    [System.Object] Join() {
        if ($this.GumbyThreadHandle.IsCompleted) {
            [System.IAsyncResult]$threadResult = $this.PSInstanceInvoker.EndInvoke($this.GumbyThreadHandle)
            [void] $this.PSInstanceInvoker.Dispose() # casting to void is equivalent of 2>&1 > $null, | Out-Null, or > $null
            return $threadResult
        }
        #System.Management.Automation.PSDataCollection`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]
        return $null
    }
    # TODO: Implement IDisposable
    [void] Dispose() {
        # TODO: make this better
        [void] $this.PSInstanceInvoker.Dispose()
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

    # Powershell doesn't have syntax for constructor chaining :(
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
        $this.Init($ThreadBody, $MaxThreads, $CleanupInterval, $initState, $gumbyhost)
    }

    # [void] AddThread([scriptblock]$ThreadCode, [object]$ThreadParams = $null) {
    #     $this.GumbyThreads += [GumbyThread]::new($this.GumbyPool, $ThreadCode, $ThreadParams)
    # }

    <#
    .SYNOPSIS
        Execute a new thread with the given code and arguments.
    #>
    [void] GumbySplit($ThreadArguments) {
        $t = [GumbyThread]::new($this.GumbyPool, $this.GumbyBody, $ThreadArguments)
        $this.GumbyThreads += $t
        Write-Output "Threads left: $($this.GumbyPool.GetAvailableRunspaces())"
    }

    [PSDataCollection[psobject][]] GumbyMerge() {
        # this **might** be faster than foreach beacuse foreach grabs an enumerator??
        $len = $this.GumbyThreads.Length
        $dirty = $false
        [PSDataCollection[psobject][]]$GumbyResults = [PSDataCollection[psobject][]]@()
        for ($i = 0; $i -lt $len; $i++) {
            [GumbyThread]$thread = $this.GumbyThreads[$i]

            if ($null -eq $thread) {
                continue
            }

            if ($thread.GumbyThreadHandle.IsCompleted) {
                $GumbyResults += ([PSDataCollection[psobject]](([PowerShell]($thread.PSInstanceInvoker)).EndInvoke($thread.GumbyThreadHandle)))
                [void] ([PowerShell]($thread.PSInstanceInvoker)).Dispose()
                $this.GumbyThreads[$i] = $null
                $dirty = $true
            }
        }

        if ($dirty) {
            $this.GumbyThreads = $this.GumbyThreads | Where-Object { $null -ne $_ }
        }

        return [PSDataCollection[psobject]]$GumbyResults
    }

    # TODO: GumbyStreams for getting all streams from all threads
    # TODO: HULK_SMASH for killing all threads, terminate all threads forcefully, first closing completed threads.
    [PSDataCollection[psobject][]] HULK_SMASH() {
        [PSDataCollection[psobject][]]$AngryResults = $this.GumbyMerge()
        $len = $this.GumbyThreads.Length

        for ($i = 0; $i -lt $len; $i++) {
            $this.GumbyThreads[$i].PSInstanceInvoker.Dispose()
            $this.GumbyThreads[$i] = $null
        }

        $this.GumbyThreads = $this.GumbyThreads | Where-Object { $null -ne $_ }

        [GC]::Collect()

        return $AngryResults
    }

    # TODO: dispose
    [void] Dispose() {
        #TODO: make this better
        $this.HULK_SMASH()
        $this.GumbyBody.Dispose()
        $this.GumbySessionState.Dispose()
        $this.GumbyPool.Dispose()
    }
}

class GumbyThreadRunner : System.IDisposable {
    <# Define the class. Try constructors, properties, or methods. #>
    GumbyThreadRunner() {
        <# Initialize the class. Use $this to reference the properties of the instance you are creating #>
    }


}

Export-ModuleMember -Function * -Class * -Cmdlet * -Alias * -Variable * -Enum *
