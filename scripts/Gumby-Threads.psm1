#!/usr/bin/env pwsh
<#
Module defines powershell classes and methods for executing multithreaded code in a runspace pool.

Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230727

object for containing a thread instance handle and powershell object for the singular thread
object for containing the collection of threads and runspace pool
object for running threads using a specified script block and a method for dispatching new threads

https://xkln.net/blog/multithreading-in-powershell--running-a-specific-number-of-threads/
#>



class GumbyThread : System.IDisposable {
    [System.Management.Automation.PowerShell] $InvokeHandle
    [System.Management.Automation.PowerShell] $TheInvoker

    GumbyThread([System.Management.Automation.PowerShell]$TheInvoker) {
        $this.TheInvoker = $TheInvoker
        $this.InvokeHandle = $TheInvoker.BeginInvoke()
    }

    [void] Join() {
        $this.TheInvoker.EndInvoke($this.InvokeHandle)
    }
}

class GumbyThreadJeffe : System.IDisposable {
    #[System.Management.Automation.PowerShell]
    hidden [System.Collections.Generic.List[GumbyThread]] $Threads
    hidden [System.Management.Automation.Runspaces.InitialSessionState] $InitialState
    hidden [System.Management.Automation.Runspaces.RunspacePool] $CoolPool

    GumbyThreadJeffe() {
        GumbyThreadJeffe([UInt32]69)
    }

    GumbyThreadJeffe([UInt32]$InitialThreadContainerSize, [System.Management.Automation.Host.PSHost]$gumbyhost = $host) {
        $this.Threads = [System.Collections.ArrayList]::new($InitialThreadContainerSize)
        $this.InitialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $this.CoolPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $InitialThreadContainerSize, $this.InitialState, $gumbyhost)
        $this.CoolPool.Open()
    }

    [void] MethodName($OptionalParameters) {
        <# Action to perform. You can use $ to reference the current instance of this class #>
    }
}

class GumbyThreadRunner : System.IDisposable {
    <# Define the class. Try constructors, properties, or methods. #>
    GumbyThreadRunner() {
        <# Initialize the class. Use $this to reference the properties of the instance you are creating #>
    }


}

Export-ModuleMember -Function * -Class * -Cmdlet * -Alias * -Variable * -Enum *
