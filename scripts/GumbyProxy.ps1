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
#>
<#
# Interesting reference material: https://github.com/jpetazzo/squid-in-a-can
#
#$ This is a web proxy script, it will eventually be a proxy to handle windows
authentication to a sharepoint server seemlessly for a tool that does not
support authentication. Eventual goal is to also have this set up as an inline
transparent proxy that handles caching too.
#
# TODO: figure out how to bind to non localhost without admin access on a non
# privileged port. This is the error:
# > .\WebProxy.ps1
# MethodInvocationException: C:\Users\\WebProxy.ps1:56:1
# Line |
#   56 |  $listener.Start()
#      |  ~~~~~~~~~~~~~~~~~
#      | Exception calling "Start" with "0" argument(s): "Access is denied."
#
# License: All rights reserved. This code is not licensed for use by anyone
# other than the author.
# Copyright: OperativeThunny (C) 2023.
#
# TODO: this code's foundational structure is broken because it was generated
# by ChatGPT.
# It needs to be changed so it can actually handle HTTP requests in a
# multithreaded manner. there is no method on $runspacePool for QueueScriptBlock.
#>

using namespace System.Net

# Verify the ability to run Start-ThreadJob, if it does not exist advise to install ThreadJob.
if (-not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
    Write-Error -BackgroundColor Red "The Start-ThreadJob command is not available. Please install the ThreadJob module."
    Write-Error -BackgroundColor Red "You can install it by running the following command:"
    Write-Error -BackgroundColor Red "Install-Module -Name ThreadJob"
    exit
}

# Create the runspace pool with the desired number of threads
# $minThreads = 1
# $maxThreads = 10
# $runspacePool = [runspacefactory]::CreateRunspacePool($minThreads, $maxThreads)
# $runspacePool.Open()

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
        While (-not [System.Threading.Tasks.Task]::WaitAll($Tasks, 200)) {}
        $Tasks.ForEach( { $_.GetAwaiter().GetResult() })
    }
}

Set-Alias -Name await -Value Wait-Task -Force

# Create a script block for processing each request
$handleIndividualRequest = {
    [cmdletbinding()]
    param(
        [System.Net.HttpListenerContext]$context
    )

    Write-Error "Handling an incoming HTTP request!"
    Write-Error $context.Request.Url

    try {
        $request = $context.Request
        $response = $context.Response
        # Get the original destination host and port
        # TODO: Do more parsing to be able to handle any port and proto (tls) etc...
        # here and where the webrequest is created to the destination server:
        $destinationHost = $request.Headers["Host"]
        $destinationPort = $request.Url.Port
        
        $destinationHost = "doesnotexist.TESTING123.example.com"
        $destinationPort = 80

        # Create a new HTTP request to the original destination
        $proxyRequest = [WebRequest]::Create("http://${destinationHost}:${destinationPort}" + $context.Request.Url.PathAndQuery)
        # Don't use WebRequest or its derived classes for new development. Instead, use the System.Net.Http.HttpClient class.
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
    }
    catch {
        # Handle any exceptions that occur during the proxying process
        $htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
        #$htout = $context.Response.OutputStream
        $htout.Write("YOU DONE MESSED UP, A-A-RON:")
        $htout.Write($_.Exception.Message)
        $htout.Write($_.Exception.StackTrace)
        $htout.Write($_)
        $htout.Flush()
        $context.Response.StatusCode = 500
        $context.Response.Close()
    }

    if ($null -ne $context) {
        $context.Dispose()
    }
}





# $dispatchHandlingThread = {
#     [cmdletbinding()]
#     param($result)
#     Write-Host "Dispatching a handling thread!"

#     if ($null -eq $result -or $null -eq $result.AsyncState) {
#         Write-Error -BackgroundColor Red "Unable to dispatch a handling thread because the result or result.AsyncState is null!"
#         throw "Unable to dispatch a handling thread because the result or result.AsyncState is null!"
#         exit
#     }

#     [System.Net.HttpListener]$listener = $result.AsyncState;
#     $context = $listener.EndGetContext($result.listnerResult);
#     $request = $context.Request
#     $response = $context.Response

#     Write-Host "We are at start thread!"

#     Start-ThreadJob -ScriptBlock $processRequestScript -ArgumentList $listener, $context, $request, $response
#     Start-Sleep -Seconds 1
#     $response.OutputStream.Close()
# }


# https://stackoverflow.com/questions/10623907/null-coalescing-in-powershell`
function Coalesce($a, $b) { if ($null -ne $a) { $a } else { $b } }
function IfNull($a, $b, $c) { if ($null -eq $a) { $b } else { $c } }
function IfTrue($a, $b, $c) { if ($a) { $b } else { $c } }
New-Alias "??" Coalesce
New-Alias "?:" IfTrue


try {
    # Create an HTTP listener and start it
    $listener = [HttpListener]::new()
    # TODO: Prefixes and SSL certs should be configurable from the command line.
    $listener.Prefixes.Add("http://127.0.0.1:8080/")
    $listener.Prefixes.Add("http://localhost:8080/")
    $listener.Start()

    Write-Host "Proxy server started. Listening on $($listener.Prefixes -join ', ')"
    Write-Host "Press Ctrl+C to stop the proxy server."

    while ($listener.IsListening) {
        # Dispatch a thread to handle the request
        #Write-Host -BackgroundColor Green "Waiting for connection."
        (Start-ThreadJob -ScriptBlock $handleIndividualRequest -ArgumentList $(await ($listener.GetContextAsync()))) | Out-Null
        #Get-Job | Receive-Job -Wait -AutoRemoveJob -Force
    }
} catch {
    Write-Host -BackgroundColor Red "An error occurred while processing the request!"
    Write-Host -BackgroundColor Yellow $_.Exception.Message
    $_   
}
finally {
    Write-Host -BackgroundColor Magenta "The proxy server shall now stop, close, and dispose!"
    Write-Host ''

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

    Write-Host 'Waiting for all jobs to finish...'

    Get-Job | Receive-Job -Wait -AutoRemoveJob -ErrorAction SilentlyContinue

    Write-Host 'Done.'
}

# vim: set ft=powershell :
