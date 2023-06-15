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

# Create the runspace pool with the desired number of threads
$minThreads = 1
$maxThreads = 10
$runspacePool = [runspacefactory]::CreateRunspacePool($minThreads, $maxThreads)
$runspacePool.Open()

# For this function info see https://stackoverflow.com/questions/16281955/using-asynccallback-in-powershell and the links in the comments.
function New-ScriptBlockCallback
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$Callback
    )
    # https://web.archive.org/web/20160404214529/http://poshcode.org/1382
    #
<#
    .SYNOPSIS
        Allows running ScriptBlocks via .NET async callbacks.

    .DESCRIPTION
        Allows running ScriptBlocks via .NET async callbacks. Internally this is
        managed by converting .NET async callbacks into .NET events. This enables
        PowerShell 2.0 to run ScriptBlocks indirectly through Register-ObjectEvent.

    .PARAMETER Callback
        Specify a ScriptBlock to be executed in response to the callback.
        Because the ScriptBlock is executed by the eventing subsystem, it only has
        access to global scope. Any additional arguments to this function will be
        passed as event MessageData.

    .EXAMPLE
        You wish to run a scriptblock in reponse to a callback. Here is the .NET
        method signature:

        void Bar(AsyncCallback handler, int blah)

        ps> [foo]::bar((New-ScriptBlockCallback { ... }), 42)

    .OUTPUTS
        A System.AsyncCallback delegate.
#>
    # Is this type already defined?
    if (-not ( 'CallbackEventBridge' -as [type])) {
        Add-Type @'
        using System;

        public sealed class CallbackEventBridge {
            public event AsyncCallback CallbackComplete = delegate { };

            private CallbackEventBridge() {}

            private void CallbackInternal(IAsyncResult result) {
                CallbackComplete(result);
            }

            public AsyncCallback Callback {
                get { return new AsyncCallback(CallbackInternal); }
            }

            public static CallbackEventBridge Create() {
                return new CallbackEventBridge();
            }
        }
'@
    }
    $bridge = [callbackeventbridge]::create()
    Register-ObjectEvent -InputObject $bridge -EventName callbackcomplete -Action $Callback -MessageData $args > $null
    $bridge.Callback
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
        While (-not [System.Threading.Tasks.Task]::WaitAll($Tasks, 200)) {}
        $Tasks.ForEach( { $_.GetAwaiter().GetResult() })
    }
}

Set-Alias -Name await -Value Wait-Task -Force

# Create a script block for processing each request
$handleIndividualRequest = {
    [cmdletbinding()]
    param(
        [HttpListener]$listener,
        [HttpListenerContext]$context,
        [HttpListenerRequest]$request,
        [HttpListenerResponse]$response
    )

    Write-Output "Handling an incoming HTTP request!"

    try {
        # Get the original destination host and port

        # TODO: Do more parsing to be able to handle any port and proto (tls) etc...
        # here and where the webrequest is created to the destination server:
        $destinationHost = $request.Headers["Host"]
        $destinationPort = $request.Url.Port

        $context.Response.Write("YOU DONE MESSED UP, A-A-RON: $($_ | ConvertTo-Json)")
        $context.Response.StatusCode = 500
        $context.Response.Close()
        $context.Dispose()
        exit;
        return $null
        # Create a new HTTP request to the original destination
        #$proxyRequest = [WebRequest]::Create("http://${destinationHost}:${destinationPort}" + $context.Request.Url.PathAndQuery)
        # Don't use WebRequest or its derived classes for new development. Instead, use the System.Net.Http.HttpClient class.
        # See https://learn.microsoft.com/en-us/dotnet/api/system.net.webrequest?view=net-7.0
        $client = [System.Net.Http.HttpClient]::new()

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
        $context.Response.Write("YOU DONE MESSED UP, A-A-RON: $($_ | ConvertTo-Json)")
        $context.Response.StatusCode = 500
        $context.Response.Close()
    }

    $context.Dispose()
}





$dispatchHandlingThread = {
    [cmdletbinding()]
    param($result)
    Write-Host "Dispatching a handling thread!"

    if ($null -eq $result -or $null -eq $result.AsyncState) {
        Write-Host -BackgroundColor Red "Unable to dispatch a handling thread because the result or result.AsyncState is null!"
        throw "Unable to dispatch a handling thread because the result or result.AsyncState is null!"
        exit
    }

    [System.Net.HttpListener]$listener = $result.AsyncState;
    $context = $listener.EndGetContext($result.listnerResult);
    $request = $context.Request
    $response = $context.Response

    Write-Host "We are at start thread!"

    Start-ThreadJob -ScriptBlock $processRequestScript -ArgumentList $listener, $context, $request, $response
    Start-Sleep -Seconds 1
    $response.OutputStream.Close()
}





try {
    # Create an HTTP listener and start it
    $listener = [HttpListener]::new()
    # TODO: Prefixes and SSL certs should be configurable from the command line.
    $listener.Prefixes.Add("http://127.0.0.1:8080/")
    $listener.Start()

    Write-Host "Proxy server started. Listening on $($listener.Prefixes -join ', ')"
    Write-Host "Press Ctrl+C to stop the proxy server."

    $successfullyObtainedBeginListenerContext = $listener.BeginGetContext(
        (New-ScriptBlockCallback -Callback $dispatchHandlingThread),
        $listener
    );

    # Process incoming requests
    while ($listener.IsListening) {
        # Don't start listening to a new request until the previous one has been handled
        if ($successfullyObtainedBeginListenerContext.IsCompleted -eq $true) {
            Write-Host "An incoming request has triggered the asynch begin get context. We will now handle it, papi."

            $successfullyObtainedBeginListenerContext = $listener.BeginGetContext(
                (New-ScriptBlockCallback -Callback $dispatchHandlingThread),
                $listener
            );

        }
    }
} catch {
    Write-Host -BackgroundColor Red "An error occurred while processing the request!"
    Write-Host -BackgroundColor Yellow $_.Exception.Message
    Write-Host -BackgroundColor Gray (ConvertTo-Json -Depth 99 $_)
}
finally {
    Write-Host -BackgroundColor Red "The proxy server shall now stop, close, and dispose!"
    # Stop the listener when done
    $listener.Stop()

    # Close the runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()

    Get-Job | Remove-Job -Force

    Write-Host '' # New line to clear background.
    Write-Host 'Done.'
}




# Here is some code stolen from the internet that I may use later:
# https://gist.github.com/nobodyguy/9950375
# There is an updated version of this code: https://gist.github.com/mark05e/089b6668895345dd274fe5076f8e1271
# $ServerThreadCode = {
#     $listener = New-Object System.Net.HttpListener
#     $listener.Prefixes.Add('http://+:8008/')

#     $listener.Start()

#     while ($listener.IsListening) {

#         $context = $listener.GetContext() # blocks until request is received
#         $request = $context.Request
#         $response = $context.Response
#         $message = "Testing server"

#         # This will terminate the script. Remove from production!
#         if ($request.Url -match '/end$') { break }

#         [byte[]] $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
#         $response.ContentLength64 = $buffer.length
#         $response.StatusCode = 500
#         $output = $response.OutputStream
#         $output.Write($buffer, 0, $buffer.length)
#         $output.Close()
#     }

#     $listener.Stop()
# }

# $serverJob = Start-Job $ServerThreadCode
# Write-Host "Listening..."
# Write-Host "Press Ctrl+C to terminate"

# [console]::TreatControlCAsInput = $true

# # Wait for it all to complete
# while ($serverJob.State -eq "Running")
# {
#      if ([console]::KeyAvailable) {
#         $key = [system.console]::readkey($true)
#         if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C"))
#         {
#             Write-Host "Terminating..."
#             $serverJob | Stop-Job
#             Remove-Job $serverJob
#             break
#         }
#     }

#     Start-Sleep -s 1
# }

# # Getting the information back from the jobs
# Get-Job | Receive-Job
########################
# This was from the internet as well:
# From: https://stackoverflow.com/questions/56058924/httplistener-asynchronous-handling-with-powershell-new-scriptblockcallback-s
# function New-ScriptBlockCallback
# {
#     [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
#     param(
#         [parameter(Mandatory)]
#         [ValidateNotNullOrEmpty()]
#         [scriptblock]$Callback
#     )

#     # Is this type already defined?
#     if (-not ( 'CallbackEventBridge' -as [type])) {
#         Add-Type @'
#             using System;

#             public sealed class CallbackEventBridge {
#                 public event AsyncCallback CallbackComplete = delegate { };

#                 private CallbackEventBridge() {}

#                 private void CallbackInternal(IAsyncResult result) {
#                     CallbackComplete(result);
#                 }

#                 public AsyncCallback Callback {
#                     get { return new AsyncCallback(CallbackInternal); }
#                 }

#                 public static CallbackEventBridge Create() {
#                     return new CallbackEventBridge();
#                 }
#             }
# '@
#     }
#     $bridge = [callbackeventbridge]::create()
#     Register-ObjectEvent -InputObject $bridge -EventName callbackcomplete -Action $Callback -MessageData $args > $null
#     $bridge.Callback
# }