#/usr/bin/env pwsh
# Interesting reference material: https://github.com/jpetazzo/squid-in-a-can
#
#$ This is a web proxy script, it will eventually be a proxy to handle windows authentication to a sharepoint server seemlessly for a tool that does not support authentication. Eventual goal is to also have this set up as an inline transparent proxy that handles caching too.
#
# TODO: figure out how to bind to non localhost without admin access on a non privileged port. This is the error:
# > .\WebProxy.ps1
# MethodInvocationException: C:\Users\\WebProxy.ps1:56:1
# Line |
#   56 |  $listener.Start()
#      |  ~~~~~~~~~~~~~~~~~
#      | Exception calling "Start" with "0" argument(s): "Access is denied."

# License: All rights reserved. (c) Operative Thunny. Not for use.

using namespace System.Net

# Create the runspace pool with the desired number of threads
$minThreads = 1
$maxThreads = 10
$runspacePool = [runspacefactory]::CreateRunspacePool($minThreads, $maxThreads)
$runspacePool.Open()

# Create a script block for processing each request
$processRequestScript = {
    param([HttpListenerContext]$context)
    #param($context)
    
    Write-Host -BackgroundColor Green "Handling an incoming HTTP request!"

    try {
        # Get the original destination host and port

        # TODO: Do more parsing to be able to handle any port and proto (tls) etc... here and where the webrequest is created to the destination server:
        $destinationHost = $context.Request.Headers["Host"]
        $destinationPort = $context.Request.Url.Port

        # Create a new HTTP request to the original destination
        $proxyRequest = [WebRequest]::Create("http://${destinationHost}:${destinationPort}" + $context.Request.Url.PathAndQuery)
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
        $context.Response.Write("YOU DONE FUCKED UP, A-A-RON: $($_ | ConvertTo-Json)")
        $context.Response.StatusCode = 500
        $context.Response.Close()
    }

    $context.Dispose()
}


try {
    # Create an HTTP listener and start it
    #$listener = New-Object System.Net.HttpListener
    $listener = [HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:8080/")
    #$listener.Prefixes.Add("https://localhost:8080/")
    $listener.Start()

    Write-Host "Proxy server started. Listening on $($listener.Prefixes -join ', ')"

    # Process incoming requests
    while ($listener.IsListening) {
        # Check if a request is available within a timeout
        if ($listener.BeginGetContext({ }, $null).AsyncWaitHandle.WaitOne(100)) {
            Write-Host "An incoming request has triggered the asynch begin get context."
            # Accept the incoming connection
            $context = $listener.EndGetContext($listener.BeginGetContext({ }, $null))

            # Submit the request processing to the runspace pool
            $runspacePool.QueueScriptBlock($processRequestScript, $context)
        }
    }
}
catch {
    Write-Host -BackgroundColor Red "An error occurred while processing the request!"
    Write-Host -BackgroundColor Red $_.Exception.Message
}
finally {
    Write-Host -BackgroundColor Red "The proxy server shall now stop, close, and dispose!"
    # Stop the listener when done
    $listener.Stop()

    # Close the runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()
}
