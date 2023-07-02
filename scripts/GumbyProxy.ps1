#!/usr/bin/env pwsh
<#
           ______                __          ____
          / ____/_  ______ ___  / /_  __  __/ __ \_________  _  ____  __
         / / __/ / / / __ `__ \/ __ \/ / / / /_/ / ___/ __ \| |/_/ / / /
        / /_/ / /_/ / / / / / / /_/ / /_/ / ____/ /  / /_/ />  </ /_/ /
        \____/\__,_/_/ /_/ /_/_.___/\__, /_/   /_/   \____/_/|_|\__, /
                                   /____/                      /____/

GumbyProxy is a flexible web proxy that can be used to intercept and modify
HTTP requests and responses, perform caching, and act as either a forward proxy
or a reverse proxy providing caching capabilities.

It is written in PowerShell and uses the .NET HttpListener class to listen for
incoming HTTP requests.

It is designed to be used as a local proxy server, but can also be used as a
gateway proxy server.

It is named after Gumby, the flexible clay character from the 1950s children's
television show The Howdy Doody Show, and also named after the Monty Python
sketch Gumby Brain Specialist.

License: All rights reserved. This code is not licensed for use by anyone other than the author at this time.
Copyright: OperativeThunny (C) 2023.

Interesting reference material:
    https://github.com/jpetazzo/squid-in-a-can
    https://www.powershellgallery.com/packages/HttpListener/1.0.2/Content/HTTPListener.psm1
    https://blog.ironmansoftware.com/powershell-async-method/
    https://gist.github.com/aconn21/946c702cfcc08d10e1c0984535765ae3
    https://www.b-blog.info/en/it-eng/implement-multi-threading-with-net-runspaces-in-powershell
    https://drakelambert.dev/2021/09/Quick-HTTP-Listener-in-PowerShell.html


$ This is a web proxy script, it will eventually be a proxy to handle windows
authentication to a sharepoint server seemlessly for a tool that does not
support authentication. Eventual goal is to also have this set up as an inline
transparent proxy that handles caching too.

TODO: figure out how to bind to non localhost without admin access on a non privileged port.

#>

using namespace System.Net

# Verify the ability to run Start-ThreadJob, if it does not exist advise to install ThreadJob.
if (-not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
    Write-Error "The Start-ThreadJob command is not available. Please install the ThreadJob module."
    Write-Error "You can install it by running the following command:"
    Write-Error "Install-Module -Name ThreadJob"
    Write-Error "Also check out this sick github repo: https://github.com/PowerShell/ThreadJob"
    exit
}

# https://blog.ironmansoftware.com/powershell-async-method/
# The below function and alias can be defined to simplify calling and awaiting async
# methods in PowerShell. The Wait-Task function accepts one or more Task objects and
# waits for them all to finish. It checks every 200 milliseconds to see if the tasks
# have finished to allow for Ctrl+C to cancel the PowerShell pipeline. Once all the
# tasks have finished, it will return their results.
function Wait-Task {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Threading.Tasks.Task[]]$Task
    )

    Begin {
        $Tasks = @()
    }

    Process {
        $Tasks += $Task
    }

    End {
        While (-not [System.Threading.Tasks.Task]::WaitAll($Tasks, 10)) {}
        $Tasks.ForEach( { $_.GetAwaiter().GetResult() })
    }
}
Set-Alias -Name await -Value Wait-Task -Force




<#
.DESCRIPTION
    Script block to handle an incoming http request. This scriptblock will be invoked by the Start-ThreadJob cmdlet.
    This scriptblock will invoke the handlers scriptblocks that are passed to it, and will return the result of the first handler to return a non null value.
    Provides a testing handler.
.PARAMETER $context
    The HttpListenerContext object that contains the request and response objects.
.PARAMETER $handlers
    An array of scriptblocks that will be invoked with the $context object as the only parameter.
    The scriptblocks should return $null if they did not handle the request, or a string if they did.
    The first handler to return a non null value will be the last handler to be invoked.
    The handlers will be invoked in the order they are specified in the array.
#>
$handleIndividualRequest = {
    [cmdletbinding()]
    param(
        [System.Net.HttpListenerContext]$context,
        [scriptblock[]]$handlers
    )

    $dispatcherAdjudicationValue = $context.Request.Headers.Get("test")

    if ($null -ne $dispatcherAdjudicationValue -and $dispatcherAdjudicationValue -eq "true") {
        Write-Output "Handling testing request."
        # Return a simple testing html5 page with a css animation:
        $html = Get-Content "TestingHTML.html"
        $html = $html -join "`n" # The Get-Content cmdlet does not return a string, it returns an array of strings, so we need to join them together.
        $response = $context.Response
        $response.StatusCode = 200
        $response.StatusDescription = "OK"
        $response.ContentLength64 = $html.Length
        $response.ContentType = "text/html"
        $htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
        $htout.Write($html)
        $htout.Flush()
        $response.Close()
        return "Test concluded."
    }

    # TODO: special header required to proxy?
    # TODO: How do real http proxies handle this?
    Write-Output "Sending the context to all the handlers until one returns a value."
    $continueHandling = $null
    foreach ($handler in $handlers) {
        $continueHandling = $(Invoke-Command $handler -ArgumentList $context)
        if ($null -ne $continueHandling) {
            return $continueHandling
        }
    }

    if ($context.Response.IsClosed) {
        Write-Error "The response was closed by a handler, so we are done."
        return "The response was closed by a handler, so we are done."
    }

    try {
        $context.Response.StatusCode = 501
        $context.Response.StatusDescription = "Not Implemented"
        $htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
        $htout.WriteLine("No handler function indicated that they handled the request by returning a non null value.")
        $htout.Flush()
        $context.Response.Close()
    } catch {
        Write-Error "Failed to close the response with an indicator of non implementation of handler for request."
    } finally {
        Write-Output "Done with this request."
    }
}

# TODO: Can this work as a function instead of a script block?
<#
.DESCRIPTION
    A script block that handles an incoming HTTP request and proxies it to a destination server assumining it is not to localhost.
.PARAMETER context
    The HttpListenerContext object that represents the request to be handled.
.OUTPUTS
    A string indicating the result of the request handling. Return $null to indicate that the request was not handled.
    A null return value will cause the next handler to be called. Do **NOT** return $null if you call close/dispose on the context, or response objects.
#>
$proxyRequest = {
    [cmdletbinding()]
    param(
        [System.Net.HttpListenerContext]$context
    )

    #Write-Error "Handling an incoming HTTP request!"
    #Write-Error $context.Request.Url

    try {
        $request = $context.Request
        $response = $context.Response
        # TODO: figure out how to be an actual http proxy or https proxy that can be used in browser settings, and figure out SOCKS5 proxying too.
        # Get the original destination host and port
        # TODO: Do more parsing to be able to handle any port and proto (tls) etc...
        # here and where the webrequest is created to the destination server:
        if ($request.HttpMethod -eq "CONNECT") {
            Write-Output "Handling a CONNECT request, expectedly a deliberate proxy request."
            # Retrieve the destination host and port from the CONNECT request.
# TODO: this.
            $destinationHost = $request.Url.Host
            $destinationPort = $request.Url.Port
            $connectionScheme = $request.Url.Scheme
        } else {
            Write-Output "Handling an expectedly transparently proxied request."
            # TODO: Do we need to handle a non proxied request differently, like if it starts with a / instead of a http://host/ ?

            # get cryptographic hash of host and url to use as a key for the cache.

            $dp = [System.Uri]::new($request.RawUrl)
            #$destinationHost = $dp.Host # TODO: what do we use here?
            $destinationHost = $request.Headers["Host"]
            $destinationPort = $dp.Port
            $connectionScheme = $dp.Scheme
            #$destinationPort = $request.Url.Port
            #$connectionScheme = $request.Url.Scheme
        }

        $hasher = [System.Security.Cryptography.SHA256]::Create() # TODO: make this a singleton object to avoid the overhead of creating it for every request.
        $rawhash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($request.RawUrl))
        $hash = $([System.BitConverter]::ToString($rawhash).Replace("-", '').ToLower())

        $msg = "Ignoring local request. The requested URL is: $($request.RawUrl)`
            The hash of the URL is: $hash`
            The destination host is: $destinationHost`
            The destination port is: $destinationPort`
            The connection scheme is: $connectionScheme`
            Path and query: $($context.Request.Url.PathAndQuery)`n"
        Write-Output $msg

        #if ($context.Request.IsLocal -eq $true -or $destinationHost -eq "localhost" -or $destinationHost -eq "127.0.0.1") {
        if ($destinationHost -eq "localhost" -or $destinationHost -eq "127.0.0.1") {
            #Write-Error "Request is local, not proxying."
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $response.StatusCode = 200
            $response.StatusDescription = "OK"
            $response.ContentLength64 = $responseBytes.Length # If we don't set the content length manually, the it gets magiced or something?
            $response.ContentType = "text/html"
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            # $htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
            # $htout.WriteLine("Ignoring local request. The requested URL is: $($request.Url))")
            # $htout.Flush()
            $response.Close()
            return "Local request not proxying."
        }

        # Write-Error "Proxying to $destinationHost on port $destinationPort using $connectionScheme"
        # Write-Output "Destination host: $destinationHost"
        # Write-Output "Destination port: $destinationPort"
        # Write-Output "Connection scheme: $connectionScheme"
        # Write-Output "Request method: $($request.HttpMethod)"
        # Write-Output "Request content type: $($request.ContentType)"
        # Write-Output "Request headers: $($request.Headers)"
        # Write-Output "Request url: $($request.Url)"
        # Write-Output "Request url path and query: $($request.Url.PathAndQuery)"
        # Write-Output "Request url absolute path: $($request.Url.AbsolutePath)"
        # Write-Output "Request url absolute uri: $($request.Url.AbsoluteUri)"
        # Create a new HTTP request to the original destination
        $proxyRequest = [WebRequest]::Create("$($connectionScheme)://$($destinationHost):$($destinationPort)$($context.Request.Url.PathAndQuery)")
        # Don't use WebRequest or its derived classes for new development. Instead, use the System.Net.Http.HttpClient class.
        # TODO: Replace WebRequest with HttpClient.
        # See https://learn.microsoft.com/en-us/dotnet/api/system.net.webrequest?view=net-7.0
        #$client = [System.Net.Http.HttpClient]::new()

        #$proxyRequest = [System.Net.HttpWebRequest]::Create("http://${destinationHost}:${destinationPort}" + $context.Request.Url.PathAndQuery)

        $proxyRequest.Method = $context.Request.HttpMethod
        $proxyRequest.ContentType = $context.Request.ContentType

        # Copy headers from the original request to the proxy request
        foreach ($header in $context.Request.Headers) {
            if ($header -ne "Host") {
                $proxyRequest.Headers.Add($header, $context.Request.Headers[$header])
            }
        }

        # Get the response from the original destination
        $proxyResponse = $proxyRequest.GetResponse()

        # Copy headers from the proxy response to the original response
        foreach ($header in $proxyResponse.Headers) {
            $context.Response.Headers.Add($header, $proxyResponse.Headers[$header])
        }

        # Copy the response content from the proxy response to the original response
        $stream = $proxyResponse.GetResponseStream()
        $stream.CopyTo($context.Response.OutputStream)
        $stream.Close()

        $context.Response.Close()

        return $true
    }
    catch {
        # Handle any exceptions that occur during the proxying process
        $htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
        #$htout = $context.Response.OutputStream
        $htout.WriteLine("YOU DONE MESSED UP, A-A-RON (There was an error handling a proxied request/response):")
        $htout.WriteLine($_.Exception.Message)
        $htout.WriteLine($($_ | ConvertTo-Json -Depth 1))
        $htout.Flush()
        $context.Response.StatusCode = 500
        $context.Response.Close()
    }
    finally {
        $context.Response.Close()
    }

    if ($null -ne $context) {
        $context.Dispose()
    }

    return $false
}



try {
    # Create an HTTP listener and start it
    $listener = [HttpListener]::new()
    # TODO: Prefixes and SSL certs should be configurable from the command line.
    # $listener.Prefixes.Add("http://127.0.0.1:8080/")
    # $listener.Prefixes.Add("http://localhost:8080/")
    $listener.Prefixes.Add("http://*:8080/")
    [HttpListenerTimeoutManager]$timeoutManager = $listener.TimeoutManager
    $timeoutManager.DrainEntityBody = [System.TimeSpan]::FromSeconds(120)
    #$timeoutManager.EntityBody = [System.TimeSpan]::FromSeconds(10) # Not supported on linux.
    #$timeoutManager.HeaderWait = [System.TimeSpan]::FromSeconds(5) # Not supported on linux.
    $timeoutManager.IdleConnection = [System.TimeSpan]::FromSeconds(5)
    #$timeoutManager.MinSendBytesPerSecond = [Int64]150 # Not supported on linux.
    #$timeoutManager.RequestQueue = [System.TimeSpan]::FromSeconds(5) # Not supported on linux.
    $listener.Start()

    Write-Host "Proxy server started. Listening on $($listener.Prefixes -join ', ')"
    Write-Host "Press Ctrl+C to stop the proxy server."

    while ($listener.IsListening) {
        # Dispatch a thread to handle the request
        # TODO: Figure out how to set the jobs to automatically output stdout to console and close and remove on their own or have the get job receive job be done asynch, maybe even in another job??
        Write-Host -BackgroundColor Green "Waiting for connection..."
        # TODO: There is a bug that when the script first starts the first two http requests have to come in slowly, or else for some reason it breaks. If a couple requests come in with a minimum time delta of .25 seconds things seem to work, then after that if I change the testing script to have no sleeps in it, then the script works appropriatly.
        (Start-ThreadJob -ScriptBlock $handleIndividualRequest -ArgumentList $(await ($listener.GetContextAsync())), @($proxyRequest) ) | Out-Null

        # Get output and remove jobs that have finished executing (hopefully not the one we just started):
        Write-Host -BackgroundColor Green "=================== Finished Thread Output: "
        Get-Job | Where-Object state -in Completed,Blocked,Failed,Stopped,Suspended,AtBreakpoint,Disconnected | Receive-Job -Wait -AutoRemoveJob -Force
        Write-Host -BackgroundColor Green "============================================"
    }
} catch {
    Write-Host -BackgroundColor Red "An error occurred while processing the request!"
    Write-Host -BackgroundColor Yellow $_.Exception.Message
    $_
}
finally {
    Write-Host -BackgroundColor Magenta "The proxy server shall now stop, close, and dispose!"
    [Console]::ResetColor()

    # Stop the listener when done
    if($null -ne $listener) {
        $listener.Stop()
        $listener.Close()
        $listener.Dispose()
    }

    # Close the runspace pool
    if ($null -ne $runspacePool) {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }

    $jobs = Get-Job

    Write-Host 'Removing any leftover background handlers...'

    $jobs | ForEach-Object {
        Write-Host "Removing jorb $($_.Id)... "
        Remove-Job -Force -Job $_
    }

    Write-Host 'Done.'
}

# vim: set ft=powershell :
