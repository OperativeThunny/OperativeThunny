#!/usr/bin/env pwsh
<#
See GumbyProxy.ps1 for a better header.
License: All rights reserved. This code is not for use by anyone other than the author at this time.
Copyright: OperativeThunny (C) 2023.

#https://webcache.googleusercontent.com/search?q=cache:TDDVRn06BJ0J:https://herringsfishbait.com/2014/09/11/powershell-get-folder-size-on-disk-one-line-command/&cd=11&hl=en&ct=clnk&gl=us&client=firefox-b-1-e
GCI C:\source -recurse | Group-Object -Property Directory |
 % {New-Object PSObject -Property @{Name=$_.Name;Size=($_.Group |
 ? {!($_.PSIsContainer)} | Measure-Object Length -sum).Sum}} |
 Sort-Object -Property Size -Descending
#>

using module ./Gumby-Threads.psm1

Set-StrictMode -Version latest
Set-PSDebug -Strict


$CACHE_DIR = "./cache"
$CACHE_ENABLED = $true
$CACHE_IGNORE_GET_PARAM = 'GumbyIgnoreCache'
$PROXY_REQUEST_TIMEOUT = 60 # seconds passed to the invoke-webrequest command for timeout connecting to remote host.
# TODO: fix this for not powershell 5.1 : https://github.com/PowerShell/PowerShell/issues/7092
$code = @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : System.Net.ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true; // :( sad trombone, sad panda :( :( :(
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp
[System.Net.ServicePointManager]::CertificatePolicy = [TrustAllCertsPolicy]::new()
#[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} # I got an error using this method about running out of runspaces.
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
        # VERY IMPORTANT: This used to be set to 200 milliseconds, but if many http requests were coming in fast enough, it would cause the script to hang. Lowering this seemed to __hide__ what I presume is a race condition **somewhere** that I have not yet figured out, I suspect its some sort of race condition in the .net layer dealing with the async tasks for the httplistener class, but I have no idea.
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
[scriptblock]$handleIndividualRequest = [scriptblock]::Create({
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

    # HTTP proxy request looks like full hostname in the GET or other METHOD line
    #Write-Output "Sending the context to all the handlers until one returns a value."
    try {
        $continueHandling = $null
        foreach ($handler in $handlers) {
            $continueHandling = $(Invoke-Command $handler -ArgumentList $context)
            if ($null -ne $continueHandling) {
                return $continueHandling
            }
        }
    } catch {
        [System.Management.Automation.ErrorRecord]$e = $_
        Write-Error "Error in request handlers: $($e.Exception.Message) $($e.Exception.StackTrace) $($e.Exception.TargetSite) $($e.Exception.Source)"
        return @($e, $e.CategoryInfo, $e.ErrorDetails, $e.Exception, $e.FullyQualifiedErrorId, $e.InvocationInfo, $e.PipelineIterationInfo, $e.ScriptStackTrace, $e.TargetObject)
    }

    if ($context.Response.IsClosed) {
        Write-Error "The response was closed by a handler, so we are done."
        return "The response was closed by a handler, so we are done."
    }

    try {
        $context.Response.StatusCode = 501
        $context.Response.StatusDescription = "Not Implemented"
        [byte[]]$byt = [System.Text.Encoding]::UTF8.GetBytes("No handler function indicated that they handled the request by returning a non null value.")
        $context.Response.OutputStream.Write($byt, 0, $byt.Length)
        $context.Response.Close()
    } catch {
        Write-Error "::`n`nFailed to close the response with an indicator of non implementation of handler for request."
        $_
        $_.Exception
        $_.Exception.Message
        $_.Exception.Source
        $_.Exception.InnerException
        $_.Exception.InnerException.Message
        $_.Exception.InnerException.Source
    } finally {
        Write-Output "Done with this request."
    }
})

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
[scriptblock]$proxyRequest = [scriptblock]::Create({
    [cmdletbinding()]
    param(
        [System.Net.HttpListenerContext]$context
    )

    function Copy-Stream {
        [OutputType([UInt64])]
        param([System.IO.Stream]$in, [System.IO.Stream]$out, [ref][byte[]]$buff)
        [UInt64]$BytesMoved = 0
        if($null -eq $buff -or ($null -eq $buff.Value -and $buff -is [ref]) ) {
            $buff = [byte[]]::new(64KB)
        } else {
            [byte[]]$buff = $buff.Value
        }
        $blen = $buff.Length #so property does not have to be accessed over and over, TODO: does this actually have any sort of performance impact on the actual IL code that gets executed?
        [UInt64]$BytesRead = 0
        while ( ($BytesRead = $in.Read($buff, 0, $blen)) -gt 0 ) {
            #Write-Error "WE COPIED $($BytesRead) BYTES!)"
            $out.Write($buff, 0, $BytesRead)
            $BytesMoved += $BytesRead
        }
        #Write-Error "WOOHOO BYTES ($BytesMoved)"
        return $BytesMoved
    }

    #Write-Error "Handling an incoming HTTP request!"
    #Write-Error $context.Request.Url

    try {
        $request = $context.Request
        $response = $context.Response
        $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
        #[System.Net.WebHeaderCollection]$headers = $response.Headers

        #$response.Headers +=
        # TODO: figure out how to be an actual http proxy or https proxy that can be used in browser settings, and figure out SOCKS5 proxying too.
        # Get the original destination host and port
        # TODO: Do more parsing to be able to handle any port and proto (tls) etc...
        # here and where the webrequest is created to the destination server:
        if ($request.HttpMethod -eq "CONNECT") {
            Write-Output "Handling a CONNECT request, expectedly a deliberate proxy request."
            # Retrieve the destination host and port from the CONNECT request.
# TODO: this.
return $false
            $destinationHost = $request.Url.Host
            $destinationPort = $request.Url.Port
            $connectionScheme = $request.Url.Scheme
        } else {
            #Write-Output "Handling a direct or proxied request to raw URL: $($request.RawUrl))"
            $rurl = $request.RawUrl
            if ($rurl.StartsWith("/")) {
                $rurl = "file://" + $rurl
            }
            $RawUrlParsed = [System.Uri]::new($rurl)
            $destinationHost = $request.Headers["Host"]
            $destinationPort = $RawUrlParsed.Port
            $connectionScheme = $RawUrlParsed.Scheme

            if ($true -and $RawUrlParsed.Host -ne $destinationHost) {
                #Write-Output "The host header and the host in the url do not match. '$($RawUrlParsed.Host)' != '$($destinationHost) != $($RawUrlParsed)' `
                #This is probably a direct request, so use the host header and the url path and query to make the request to the destination server, if it is not localhost."

                $destinationPort = 80
                $connectionScheme = "http"

                if ($destinationHost.IndexOf(":") -gt 0) {
                    # Handle the case of a host header that includes a port number.
                    try {
                        $destinationPort = $destinationHost.Substring($destinationHost.IndexOf(":") + 1)
                        $destinationHost = $destinationHost.Substring(0, $destinationHost.IndexOf(":"))
                        $connectionScheme = $request.Url.Scheme
                    } catch {
                        Write-Error "Failed to parse the host header as a URI. The host header is: '$($destinationHost)'"
                    }
                }

                #Write-Output "The host parsed is: $($hostParsed)"
            }
        }

        if ($null -eq $destinationHost) {
            $destinationHost = $request.Url.Host
        }

        $destinationHost = $destinationHost.ToLower().Trim()
        $destinationPathAndQuery = $request.Url.PathAndQuery

        #if ($context.Request.IsLocal -eq $true -or $destinationHost -eq "localhost" -or $destinationHost -eq "127.0.0.1") {
        if ($destinationHost -eq "localhost" -or $destinationHost -eq "127.0.0.1") {
            $msg = "`n
                Ignoring local request. The requested URL is: $($request.RawUrl)`
                The hash of the URL is: $hash`
                The destination host is: $destinationHost`
                The destination port is: $destinationPort`
                The connection scheme is: $connectionScheme`
                Path and query: $destinationPathAndQuery`n`n"

            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $response.KeepAlive = $false
            $response.StatusCode = 200
            $response.StatusDescription = "OK"
            $response.ContentLength64 = $responseBytes.Length # If we don't set the content length manually, then it gets automatically set or something? (me, later: no it needs to be set.)
            $response.ContentType = "text/html"
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
            $response.OutputStream.Close()
            $response.Close()
            return "Local request not proxying."
        }

        # TODO: NOTE: function for special case corrections goes here
        if ($destinationHost -eq "i.imgur.com") {
            $destinationHost = "somethingelse.example.com"
            $destinationPort = 443
            $connectionScheme = "https"
            $SHAREPOINT_OVERRIDE = $true # TODO: change this variable once file is complete.
        }

        # ignore favicon
        if ($rurl -eq "file:///favicon.ico") {
            $response.StatusCode = 200
            $response.StatusDescription = "OK no vavicon tho"
            $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
            $context.Response.Cloase()
            return $true
        }

        $FinalDestination = "$($connectionScheme)://$($destinationHost):$($destinationPort)$($destinationPathAndQuery)"

        # Do not bother with the cache if the get parameter has been added to the URL to bypass cache.
        $IgnoreCache = $null -ne $Global:CACHE_IGNORE_GET_PARAM -and $FinalDestination.IndexOf("$($Global:CACHE_IGNORE_GET_PARAM)") -gt -1

        if (!$IgnoreCache -and $Global:CACHE_ENABLED) {
            if (!($Global:HASHER_SINGLETON)) {
                $Global:HASHER_SINGLETON = [System.Security.Cryptography.SHA256]::Create()
            }
            $hasher = $Global:HASHER_SINGLETON
            if ($null -eq $Global:CACHE_DIR) {
                Write-Error "The cache is enabled and we are to cache, but the cache directory is null. Terminating."
                exit -66
            }

            # get hash of host and url to use as a key for the cache directory:
            $rawhash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FinalDestination))
            $hash = $([System.BitConverter]::ToString($rawhash).Replace("-", '').ToLower())
            $hashPrefix = $hash.Substring(0, 2)
            $hmux = $false
            try {
                $mux = [System.Threading.Mutex]::new($false, "CreateCacheMutexDictionary") # TODO: Singleton this so we don't have to create a new mutex every time.
                $hmux = $mux.WaitOne([System.Threading.Timeout]::Infinite, $false) | Out-Null
                if (!($Global:CacheFileMutexDictionary)) {
                    $Global:CacheFileMutexDictionary = [System.Collections.Generic.Dictionary[string, System.Threading.Mutex]]@{}
                }
                if (!($Global:CacheFileMutexDictionary.ContainsKey($hashPrefix))) {
                    $gotExistingMut = $false
                    $mutPossible = [System.Threading.Mutex]::TryOpenExisting($hash, [ref]$gotExistingMut)
                    if (!$gotExistingMut) {
                        $Global::CacheFileMutexDictionary[$hash] = [System.Threading.Mutex]::new($false, $hash)
                    } else {
                        $Global:CacheFileMutexDictionary[$hash] = $mutPossible
                    }
                }
                $CacheFileMutexInstance = $Global:CacheFileMutexDictionary[$hash] # [System.Threading.Mutex]::new($false, $hash)
            } catch {
                $_
            } finally {
                if ($hmux){
                    $mux.ReleaseMutex()
                    $mux.Dispose()
                }
            }

            if ($null -eq $CacheFileMutexInstance) {
                Write-Error "oops we dont have a mutex!"
                exit -66
            }

            $cacheRoot = $Global:CACHE_DIR
            # TODO: Handle race condition possibilities here for creating the cache directory and file, possibly using some sort of promise if promises are in powershell?
            $cacheDir = "$($cacheRoot)/$($hashPrefix)"
            $cacheFile = "$($cacheDir)/$($hash)"
            $CacheContentTypesFile = "$($cacheDir)/000001ContentTypes.txt"

            if (-not (Test-Path -Path $cacheDir)) {
                Write-Output "Creating cache directory: $cacheDir"
                New-Item -Path $cacheDir -ItemType Directory | Out-Null
            }

            if ((Test-Path -Path $cacheFile)) {
                [System.Boolean]$hasCacheFileMutex = $false
                try {
                    [System.Boolean]$hasCacheFileMutex = $CacheFileMutexInstance.WaitOne([System.Threading.Timeout]::Infinite, $false)# | Out-Null # figured out while transcribing this is why the mutexes were getting abandoned lol...

                    $response.ContentType = "text/html"
                    if (Test-Path $CacheContentTypesFile) {
                        $contentTypeMap = Get-Content $CacheContentTypesFile | ConvertFrom-StringData
                        if ($contentTypeMap.ContainsKey($hash)) {
                            $response.ContentType = $contentTypeMap[$hash]
                        } else {
                            Write-Host -BackgroundColor Red "Defaulting to text/html content type $($hash) :: $($FinalDestination) :-> $($cacheFile) :("
                        }
                    }

                    # The file exists, return it directly to the response stream and return.
                    # TODO: handle cache invalidation {insert meme about the two hardest things in computer science being naming things, counting, and cache invalidation}
                    [System.IO.FileStream]$responseFileStream = [System.IO.File]::OpenRead($cacheFile)
                    $response.StatusCode = 200
                    $response.StatusDescription = "OK"
                    $response.ContentEncoding = [System.Text.Encoding]::UTF8 # TODO: change this for things like images and other binary content.
                    $response.KeepAlive = $true
                    $response.Headers.Set([System.Net.HttpRequestHeader]::Server, "GumbyProxy Alpha")
                    $response.ContentLength64 = $responseFileStream.Length
                    $bytesCopied = Copy-Stream ([System.IO.Stream]($responseFileStream)) ([System.IO.Stream]($response.OutputStream))
                    $response.OutputStream.Flush()
                    $responseFileStream.Close()

                    if ($bytesCopied -ne $responseFileStream.Length) {
                        Write-Error "For some reason the amount of bytes in the cache file was not the same as the number of bytes copied to the output stream.... idk man something is weird up in this fine establishment."
                    }

                    if ($response.OutputStream.CanWrite) {
                        $response.Close()
                    } else {
                        Write-Error "Unable to close response after writing cached content to response stream."
                    }
                } catch {
                    Write-Error "ERROR WRITING RESPONSE IN FILE EXISTS $($response.ContentType) = $($FinalDestination) :: $($hash) :-> $($cacheFile) :("
                } finally {
                    if ($hasCacheFileMutex) { # TODO: For some reason this finally block never gets executed and we occasionally get failures in acquiring mutexes after a long runtime duration because the mutex was abandoned by a previous thread somehow.
                        $CacheFileMutexInstance.ReleaseMutex()
                    }
                }


                # TODO: If the cache is older than X {time unit} then go ahead and grab the content from the server and update the cache file after we have already returned the cached content to the client.
                return @{
                    result = $true
                    message = "CACHE Successful proxy"
                } # RETURN
            } # end cache file exisetence check
        }




        # Create a new HTTP request to the original destination
# This is where the request to the final destination server is made, so I put these pound signs here to make it more impactful {to notice later while scrolling code} :)
##############################################################################
        # Get the response from the original destination
        $IgnoredHeadersString = @"
Host
Connection
User-Agent
Content-Length
Accept
Transfer-Encoding
Referer
Accept-Encoding
KeepAlive
Close
Upgrade-Insecure-Requests
X-FRAME-OPTIONS
Persistent-Auth
X-Content-Type-Options
Strict-Transport-Security
Sec-Fetch-Dest
Sec-Fetch-Mode
Sec-Fetch-Site
Sec-Fetch-User
sec-ch-ua
sec-ch-ua-mobile
sec-ch-ua-platform
"@
        #$ignoredHeaders = "Host", "Connection", "User-Agent", "Content-Length"
        $ignoredHeaders = (((($IgnoredHeadersString -replace "`r", "") -split "`n") | Where-Object { $_.Trim() -ne "" }) -join ",") -split ","
        try {
            if (!($Global:SESSION_SINGLETON)) { # This has to be shared between threads. TODO: Validate the comment.
                $Global:SESSION_SINGLETON = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
                Write-Error "GLOBAL SESSION SINGLETON MISSING!"
            }
            $session = $Global:SESSION_SINGLETON
            # TODO: This is bad. I guess we will have to (eventually^(tm)) figure out some method of session differentiation for different clients or different actual web session sin the browser of the same client. (future me: sorry in advance)
            $session.UserAgent = $request.UserAgent
            [System.Collections.Generic.Dictionary[string,string]]$headersDictionary = $([System.Linq.Enumerable]::ToDictionary(
                [System.Linq.Enumerable]::Where(
                    $request.Headers.AllKeys,
                    [Func[string,bool]]{param($v) (($ignoredHeaders -ne $v).Length -eq $ignoredHeaders.Length) }
                ),
                [Func[string,string]]{param($v) $v },
                [Func[string,string]]{param($v) $request.Headers[$v] }
            ))

            # We have to deal with the cookies for some reason that I dont know, the domain field was blank....
            try {
                ForEach ($cookie in $request.Cookies.GetEnumerator()) {
                    ([System.Net.Cookie]$cookie).Domain = $destinationHost # WHY??????? WHY IS THIS BLANK BEFORE HERE????
                    # I just realized its because coming from the client request, no domain information is sent for the cookies because the server doesn't care about it, it just wants all the cookies the client will send it.
                    $session.Cookies.Add([System.Net.Cookie]$cookie)
                }
            } catch {
                $_
                $_.Exception
                $_.InvocationInfo
                $_.Exception.Source
                $_.ScriptStackTrace
                $_.ErrorDetails
                throw $_
            }

            foreach ($header in $headersDictionary.Keys) {
                Write-Output "REQUEST HEADER: $($header):=> $($headersDictionary[$header])"
            }

            if ($request.HttpMethod -ne "GET") {
                # TODO: Other HTTP Verbs. The verb is verboten
                Write-Error "Method was not GET, dunno how to proceed my guy $($request)"
                return $null # returning null to the handler dispatch func for it to keep trying other handler functions if any others are defined.
                # Guard clause FTW!
            }

            #if ($request.HttpMethod -eq "GET") {
            $ProgressPreference = "SilentlyContinue"
            # This can't be
            # [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]
            # or
            # [Microsoft.PowerShell.Commands.HtmlWebResponseObject]
            # because for requests other than for a web page such as images, these object types will not be returned by the invoke-webrequest cmdlet.
            # because, for images for example, not everything returned from te IWR cmdlet is that class
            [Microsoft.PowerShell.Commands.WebResponseObject]$proxyResponse = Invoke-WebRequest `
                -UseBasicParsing `
                -UseDefaultCredentials `
                -DisableKeepAlive `
                -UserAgent $request.UserAgent `
                -TimeoutSec 60 `
                -Uri "$($FinalDestination)" `
                -Headers $headersDictionary `
                -WebSession $session

            if ($SHAREPOINT_OVERRIDE -and (($proxyResponse.Headers["Content-Type"]).IndexOf("text/html") -gt -1) -and (($proxyResponse.RawContent.IndexOf("Document was created with the newer version of the form template") -gt -1) -or (($proxyResponse.RawContent.IndexOf("Schema validation found non-datatype errors.")) -gt -1) -or ($proxyResponse.RawContent.IndexOf("There has been an error while loading the form") -gt -1)) ) {
                # Redo the requeset because it is one of the broken sharepoint responses for the infopath form
                Write-Error "We done diggity dog goniit we gotta POST after GET :("
                [Microsoft.PowerShell.Commands.WebResponseObject]$proxyResponse = Invoke-WebRequest `
                    -UseBasicParsing `
                    -UseDefaultCredentials `
                    -DisableKeepAlive `
                    -UserAgent $request.UserAgent `
                    -TimeoutSec 120 `
                    -Uri "$($FinalDestination)" `
                    -Headers $headersDictionary `
                    -WebSession $session `
                    -Method POST `
                    -ContentType "multipart/form-data; boundary=----WebKitFormBoundarytbV4bcE0wmdl3qbS" `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes("------WebKitFormBoundarytbV4bcE0wmdl3qbS$([char]13)$([char]10)Content-Disposition: form-data; name=`"FormControl_InfoPathContinueLoading`"$([char]13)$([char]10)$([char]13)$([char]10)1$([char]13)$([char]10)------WebKitFormBoundarytbV4bcE0wmdl3qbS$([char]13)$([char]10)"))

                if ((($proxyResponse.RawContent.IndexOf("Schema validation found non-datatype errors.")) -gt -1) -or ($proxyResponse.RawContent.IndexOf("There has been an error while loading the form") -gt -1) ) {
                    Write-Error "We are really really oopsed on this one!"
                    Write-Error $FinalDestination
                    Write-Error $cacheDir
                    Write-Output "Error with $($FinalDestination) :: $($cacheDir)"
                    Write-Output "Cache directory attempted: $($cacheDir)"
                }
            }
            #} # end if GET
        } catch {
            Write-Error "Failed to get response from destination server. '$($FinalDestination)': $($_.Exception.Message)"
            #$htout = [System.IO.StreamWriter]::new($context.Response.OutputStream)
            $ErrMsgToClient = [string[]]@()
            $ErrMsgToClient += $("YOU DONE MESSED UP A-A-RON!`n$(`"=`"*80)`n'$($FinalDestination)': $($_.Exception.Message)")
            $ErrMsgToClient += $("`nΩ`n")
            $ErrMsgToClient += $("⌠")
            $ErrMsgToClient += $("| x dx = .5*x^2 + C")
            $ErrMsgToClient += $("⌡")
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception.Source.Line)
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception.Message)
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception)
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception.InnerException)
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception.Source)
            $ErrMsgToClient += $("`n`n")
            $ErrMsgToClient += $($_.Exception.StackTrace)
            $ErrMsgToClient += $("`n`n`n§")
            # $BytesToClient = [System.Text.Encoding]::UTF8.GetBytes($ErrMsgToClient -join "`n")
            # $response.OutputStream.Write($BytesToClient, 0, $BytesToClient.Length)
            # $response.ContentLength64 = $BytesToClient.Length
            # $response.StatusDescription = "Internal Server Error"
            # $response.StatusCode = 500
            # $response.OutputStream.Flush()
            # $response.Close()
            # return "Failed to get response from destination server. '$($FinalDestination)': $($_.Exception.Message)"
            [System.Net.WebException]$webEx = $_ -as [System.Net.WebException]
            if ($null -ne $webEx) {
                $webEx.Response | ConvertTo-Json
                $webEx.Status | ConvertTo-Json
                $ErrMsgToClient += "Web exception occurred: "
                $ErrMsgToClient += $($webEx.Response | ConvertTo-Json)
                $ErrMsgToClient += $($webEx.Status   | ConvertTo-Json)
            }
            $ErrMsgToClient = $ErrMsgToClient -join "`n"
            [byte[]]$BytesToClient = [System.Text.Encoding]::UTF8.GetBytes($ErrMsgToClient)
            $response.ContentType = "text/plain"
            $response.KeepAlive = $false
            $response.ContentLength64 = $BytesToClient.Count
            $response.StatusCode = 418
            $response.StatusDescription = "I am a teapot. Soy una tetera. Je suis une théière. Ich bin eine Teekanne."
            $response.OutputStream.Write($BytesToClient, 0, $BytesToClient.Length)
            $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
            $response.Close()
            return $false
        }
#########################################################################
        # Copy headers from the proxy response to the original response
        #$ignoredHeaders = "Host", "Connection", "User-Agent", "Content-Length"
        $ignoredHeaders = @"
Content-Length
Connection
Transfer-Encoding
Upgrade-Insecure-Requests
X-FRAME-OPTIONS
Persistent-Auth
X-Content-Type-Options
Strict-Transport-Security
"@
        $ignoredHeaders = (((($ignoredHeaders -replace "`r", "") -split "`n") | Where-Object { $_.Trim() -ne "" }) -join ",") -split ","
        foreach ($header in $proxyResponse.Headers.Keys) {
            #Write-Output "RESPonSE HEADER $($header): $($proxyResponse.Headers[$header])"
            if ($ignoredHeaders -notcontains $header) {
                $response.Headers.Set($header, $proxyResponse.Headers[$header])
            }
        }

        # Add any cookies from a set cookie header to the cookie jar.
        # TODO: THIS IS BEYOND INSECURE. FOR THE LOVE OF ALL THAT IS HOLY DO NOT USE THIS IN A CONTINUOUSLY RUNNING PRODUCTION SITUATION.
exit -99 # here for the github so people dont accidently blindly use this script.
        # TODO: this is obviously really bad for security....
        $cookiesToSetUnsecure = $proxyResponse.Headers["Set-Cookie"]
        if ($null -ne $cookiesToSetUnsecure) {
            # Strip secure and httponly...........
            if ($cookiesToSetUnsecure -isnot [string]) {
                foreach ($setCookie in $cookiesToSetUnsecure.Keys) {
                    $replacement = $cookiesToSetUnsecure[$setCookie] #-replace "; Secure", "" -replace "; HttpOnly", ""
                    $replacement = $replacement.Replace(" secure;", "")
                    $replacement = $replacement.Replace(" Secure;", "")
                    $replacement = $replacement.Replace(" httponly;", "")
                    $replacement = $replacement.Replace(" HttpOnly;", "")
                    $replacement = $replacement.Replace(" HttpOnly", "")
                    $cookiesToSetUnsecure[$setCookie] = $replacement
                }
            } else {
                $replacement = $cookiesToSetUnsecure.Replace(" secure;", "") #-replace "; Secure", "" -replace "; HttpOnly", ""
                $replacement = $replacement.Replace(" Secure;", "")
                $replacement = $replacement.Replace(" httponly;", "")
                $replacement = $replacement.Replace(" HttpOnly;", "")
                $cookiesToSetUnsecure = $replacement
            }

            $response.Headers["Set-Cookie"] = $cookiesToSetUnsecure

            $CookieInfoObject =
            $session.Cookies.GetType().InvokeMember(
                'm_domainTable',
                [System.Reflection.BindingFlags]::GetField -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance,
                $null,
                $session.Cookies,
                @()) # TODO: I know this is an atrocity, a crime against humanity, to use reflection in this way and this is not portable and could break on a .net framework update.
            if ($null -eq $CookieInfoObject) {
                Write-Error "I know this is an atrocity, a crime against humanity, to use reflection in this way and this is not portable and could break on a .net framework update."
            }
            ForEach ($cook in $CookieInfoObject.Keys) {
                ForEach ($path in $CookieInfoObject[$cook].Values) { #This is a PathList type, a private class in the implementation from the .net framework.
                    ForEach ($actualCookies in [System.Net.CookieCollection]$path) {
                        [System.Net.Cookie]$monster = $actualCookies
                        $monster.Secure = $false
                        $monster.HttpOnly = $false
                        $session.Cookies.Add([System.Net.Cookie]$monster)
                    }
                }
            }
        }

        # Create two copies of the response stream, send one to the client, and save one to the cache.

        # $Global:SESSION_SINGLETON = $session
        $response.ContentEncoding = [System.Text.Encoding]::UTF8
        $response.ContentType = $proxyResponse.Headers["Content-Type"]
        if ($proxyResponse.Headers["Transfer-Encoding"] -match "chunked") {
            $response.SendChunked = $true
        }
        if ($FinalDestination.IndexOf("css") -gt -1) {
            $response.ContentType = "text/css"
        }

        $stream = $proxyResponse.RawContentStream

        # IMPORTANT: don't try to mess with images.
        # Peform hostname string replacements in the response to ensure the client can correctly load all assets of the webpage through this proxy:
        if (!($response.ContentType.IndexOf("image") -gt -1) -and $SHAREPOINT_OVERRIDE ) {
            # find and replace {redacted} strings with ones that re-reference the original destination.
            #[byte[]] $searchBuffer = [byte[]]::new(16KB)
            [byte[]] $searchBuffer = [byte[]]::new(161993)
            [System.IO.MemoryStream] $memStream = [System.IO.MemoryStream]::new(161993)
            [uint32]$read = [uint32]0

            while ( ($read = $stream.Read($searchBuffer, 0, $searchBuffer.Length)) -gt 0) {
                # TODO: This iwll fail if the string is split across a buffer boundry, but maybe I dont have to deal with handling that for this specific usage... (message for future me: sorry)
                #Write-Output "Read $($read) bytes from stream to replace"
                [string]$buffStr = [System.Text.Encoding]::UTF8.GetString($searchBuffer, 0, $read) # this might do an allocation... oh well its already F'd anyway from not handling the special case
                if ($buffStr.IndexOf("realhost.example.com") -gt -1) {
                    $buffStr = $buffStr.Replace("https://realhost.example.com:12345", "http://$($destinationHost):8080")
                    $buffStr = $buffStr.Replace("https:\/\/realhost.example.com:12345", "http:\/\/$($destinationHost):8080")
                    $buffStr = $buffStr.Replace("https:\u002f\u002frealhost.example.com:12345", "http:\u002f\u002f$($destinationHost):8080")
                    $buffStr = $buffStr.Replace("realhost.example.com\u003a12345", "$($destinationHost)\u003a8080")
                    $buffStr = $buffStr.Replace("realhost.example.com%3a12345", "$($destinationHost)%3a8080")
                    $buffStr = $buffStr.Replace("realhost.example.com:12345", "$($destinationHost):8080")
                }
                # fix error html in the xml responses:
                #$buffStr = $buffStr.Replace("%3c%2fa>", "</a>")
                if ($buffStr -ne ($buffStr = $buffStr.Replace("%3c%2fa>", "</a>"))) {
                    Write-Error "derp derp derp we made a error html replacement!"
                    Write-Error "Replaced %3c%2fa> with </a>"
                }
                [byte[]] $replacedStrBytes = [System.Text.Encoding]::UTF8.GetBytes($buffStr)
                $memStream.Write($replacedStrBytes, 0, $replacedStrBytes.Length)
            }
            $memStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            $stream = $memStream
        }

        if (!$ignoreCache -and $Global:CACHE_ENABLED) {
            # clear the file if it exists cuz we went through the trouble of getting the response stream already.
            if (Test-Path -Path $cacheFile) {
                #[System.IO.File]::Delete($cacheFile)
                #Remove-Item $cacheFile
                Write-Error "The cache file exists, and we made it to the point where we want to write the cache file, so something weird happened.`n`n$($response.ContentType) = $($FinalDestination) :: $($hash) :-> $($cacheFile) :("
            }

            [System.Boolean]$hasHandle = $false
            try {
                #$cacheFileReadStream = [System.IO.File]::OpenRead($cacheFile)
                #$cacheFileReadStream.CopyTo($response.OutputStream)
                [System.Boolean]$hasHandle = $CacheFileMutexInstance.WaitOne([System.Threading.Timeout]::Infinite, $false)# | Out-Null # wow the out null is why the mutexes were occasionally being zombied... weird...
                "$($hash)=$($response.ContentType)" | Out-File -FilePath $CacheContentTypesFile -Append
                $cacheStream = [System.IO.File]::OpenWrite($cacheFile)
                $bytesCopied = Copy-Stream ([System.IO.Stream]($stream)) ([System.IO.Stream]($cacheStream))
                $cacheStream.Close()
                $response.ContentLength64 = $bytesCopied
                $stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
                Copy-Stream ($stream) ($response.OutputStream) | Out-Null
                $cacheStream.Close()
                $stream.Close()
            } catch {
                Write-Error "Unable to write response to the client (THIS IS AT THE VERY END OF THE HANDLER AFTER HANDLING SPECIAL CASES FOR THE EXACT INSTANTIATION OF THIS SCRIPT): $($FinalDestination) :: $($hash) :-> $($cacheFile) :("
                $_
                $_.Exception
                $_.Exception.Source
                Write-Error $_
            } finally {
                #Write-Output "pre release mutex $($hasHandle.GetType().FullName) $($hasHandle) <-- has handle??"
                if ($hasHandle) {
                    Write-Output "Release Mutex!!!!!!!!!!!!!!"
                    $CacheFileMutexInstance.ReleaseMutex() | Out-Null
                }
            }
        } else {
            Write-Host -Back Red "We don't need no stinking cache!"
            $stream.CopyTo($response.OutputStream) # TODO: Replace this with the copy stream cmdlet.
        }
        $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
        $response.OutputStream.Flush()
        $response.OutputStream.Close()
        $response.Close()

        return [PSCustomObject]@{
            result = $true
            message = "Successful completion of proxying request."
        }
    } catch {
        # Handle any exceptions that occur during the proxying process
        $resp  = [string[]]@()
        $resp += $("(There was an error handling a proxied request/response):")
        $resp += $($_.Exception.Message)
        $resp += $($_.Exception.Source)
        $resp += $($_.Exception.Source.Line)
        [byte[]]$rbytes = [System.Text.Encoding]::UTF8.GetBytes(($resp -join "`n====`n"))
        $response.Headers.Set([System.Net.HttpResponseHeader]::Server, "GumbyProxy Alpha")
        $context.Response.StatusCode = 500
        $response.KeepAlive = $false
        $response.ContentLength64 = $rbytes.Count
        $response.OutputStream.Write($rbytes, 0, $rbytes.Length)
        $response.OutputStream.Flush()
        $context.Response.Close()
        return $_
    } finally {
#        "Finally block at the end of the proxy handler."
    }
    return $null # return null here so the handler dispatch function can try other handlers if any are defined.
})



try {
    # Create an HTTP listener and start it
    [System.Net.HttpListener]$listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:8080/") # you need administrator privileges on windows to make this listen on a non localhost IP reachable from external. probably because this is using HTTP.sys which is a kernel level driver on windows and having kernel level code exposed as a network serviece has not generally worked out well for windows in the past.
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).DrainEntityBody = [System.TimeSpan]::FromSeconds(120)
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).EntityBody = [System.TimeSpan]::FromSeconds(50) # NO workie on linux
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).HeaderWait = [System.TimeSpan]::FromSeconds(55) # NO LINUX
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).IdleConnection = [System.TimeSpan]::FromSeconds(55)
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).MinBytesPerSecond = [Int64]150 # No linux
    ([System.Net.HttpListenerTimeoutManager]($listner.TimeoutManager)).RequestQueue = [System.TimeSpan]::FromSeconds(55) # no linux
    $listener.Start()

    Write-Host "Proxy server started. Listening on $($listener.Prefixes -join ', ')"
    Write-Host "Press Ctrl+C to stop the proxy server."

    [scriptblock[]] $handlerArray = [scriptblock[]]@($proxyRequest)
    [System.Management.Automation.Runspaces.InitialSessionState]$InitialSessionStateInstance = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    # todo: hashmap with variable_name => value and loop over making new sessionstatevariableentries for each one and adding them to the init state.
    $sussySes = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
        "SESSION_SINGLETON",
        [Microsoft.PowerShell.Commands.WebRequestSession]::new(),
        "this is a description field and I don't know why it is here!"
    )
    $cdir = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
        "CACHE_DIR",
        $CACHE_DIR,
        "this is a description field and I don't know why it is here!"
    )
    $cenabled = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
        "CACHE_ENABLED",
        $CACHE_ENABLED,
        "this is a description field and I don't know why it is here!"
    )
    $ptimeout = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
        "PROXY_REQUEST_TIMEOUT",
        $PROXY_REQUEST_TIMEOUT,
        "this is a description field and I don't know why it is here!"
    )
    # $hasherinst = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
    #     "HASHER_SINGLETON",
    #     $HASHER_SINGLETON,
    #     "this is a description field and I don't know why it is here!"
    # )
    $cignore = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
        "CACHE_IGNORE_GET_PARAM",
        $CACHE_IGNORE_GET_PARAM,
        "this is a description field and I don't know why it is here!"
    )
    $InitialSessionStateInstance.Variables.Add($sussySes)
    $InitialSessionStateInstance.Variables.Add($cdir)
    $InitialSessionStateInstance.Variables.Add($cenabled)
    $InitialSessionStateInstance.Variables.Add($ptimeout)
    #$InitialSessionStateInstance.Variables.Add($hasherinst)
    $InitialSessionStateInstance.Variables.Add($cignore)
    $ThreadManager = [GumbyThreadJeffe]::new($handleIndividualRequest, 100, 10, $InitialSessionStateInstance, $host)

    while ($listener.IsListening) {
        $ThreadManager.GumbyStreams()
        $ThreadManager.GumbyMerge()

        # Dispatch a thread to handle the request
        Write-Host -BackgroundColor Green "Waiting for connection..."
        # TODO: There is a bug that when the script first starts the first two http requests have to come in slowly, or else for some reason it breaks. If a couple requests come in with a minimum time delta of .25 seconds things seem to work, then after that if I change the testing script to have no sleeps in it, then the script works appropriatly.

        $ThreadManager.GumbySplit( @($(await ($listener.GetContextAsync())), $handlerArray) )

        Write-Host -BackgroundColor Green "======== Finished Thread Output: "
        $ThreadManager.GumbyStreams()
        $ThreadManager.GumbyMerge()
        Write-Host -BackgroundColor Green "================================"
        # Get output and remove jobs that have finished executing (hopefully not the one we just started):
        $jobs = (Get-Job | Where-Object state -in Completed,Bloacked,Failed,Stopped,Suspended,AtBreakpoint,Disconnected)
        if ($null -ne $jobs -and $jobs.Length -gt 0) {
            Get-Job | Where-Object state -in Completed,Bloacked,Failed,Stopped,Suspended,AtBreakpoint,Disconnected | Receive-Job -Wait -AutoRemoveJob -Force
        }

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

    Write-Host 'HULK SMASH ALL THREADS!'

    $ThreadManager.HULK_SMASH()
    $ThreadManager = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    Write-Host 'Done.'
}

# vim: set ft=powershell :
