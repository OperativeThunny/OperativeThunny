#/usr/bin/env pwsh
# Interesting reference material: https://github.com/jpetazzo/squid-in-a-can
#$ This is a web proxy script, it will eventually be a proxy to handle windows authentication to a sharepoint server seemlessly for a tool that does not support authentication. Eventual goal is to also have this set up as an inline transparent proxy that handles caching too.
# TODO: Documentation
# TODO: figure out how to bind to non localhost without admin access on a non privileged port. This is the error:
# > .\WebProxy.ps1
# MethodInvocationException: C:\Users\\WebProxy.ps1:56:1
# Line |
#   56 |  $listener.Start()
#      |  ~~~~~~~~~~~~~~~~~
#      | Exception calling "Start" with "0" argument(s): "Access is denied."
# Proxy server started. Listening on http://+:8080/
# MethodInvocationException: C:\Users\\WebProxy.ps1:70:1
# Line |
#   70 |  $listener.Stop()
#      |  ~~~~~~~~~~~~~~~~
#      | Exception calling "Stop" with "0" argument(s): "Cannot access a disposed object. Object name: 'System.Net.HttpListener'."

# TODO: Figure out error where the script can't be killed with CTRL+C from the command line. It hangs on the getContext line

# License: All rights reserved. (c) Operative Thunny. Not for use.

# Create the runspace pool with the desired number of threads
$minThreads = 1
$maxThreads = 10
$runspacePool = [runspacefactory]::CreateRunspacePool($minThreads, $maxThreads)
$runspacePool.Open()

# Create a script block for processing each request
$processRequestScript = {
    param($context)

    try {
        # Get the original destination host and port

        $destinationHost = $context.Request.Headers["Host"]
        $destinationPort = $context.Request.Url.Port

        # Create a new HTTP request to the original destination
        $proxyRequest = [System.Net.WebRequest]::Create("http://${destinationHost}:${destinationPort}" + $context.Request.Url.PathAndQuery)
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
        $context.Response.StatusCode = 500
        $context.Response.Close()
    }

    $context.Dispose()
}

# Create an HTTP listener and start it
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:8080/")
$listener.Start()

Write-Host "Proxy server started. Listening on http://+:8080/"

# Process incoming requests
while ($listener.IsListening) {
    # Accept an incoming connection
    $context = $listener.GetContext()

    # Submit the request processing to the runspace pool
    $runspacePool.QueueScriptBlock($processRequestScript, $context)
}

# Stop the listener when done
$listener.Stop()

# Close the runspace pool
$runspacePool.Close()
$runspacePool.Dispose()
