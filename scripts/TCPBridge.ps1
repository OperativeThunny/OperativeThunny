#!/usr/bin/env pwsh
<#
This is a stream socket layer TCP bridge that binds to specified IP and port and
connects to specified remote IP endpoint and forwards traffic between the two.
Like a simpler netcat. Idk if windows STDIN and STDOUT will be redirectable to a
socket like on linux, but we'll give 'er the ol' college try.

Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230714

Copyright (C) 2023 Operative Thunny. All rights reserved. Eventually a license
will be decided upon, but for now all rights reserved.

This particular version uses RunspacePool threads to handle things in parallel.

The other one will use select instead of poll to avoid an allocation of an
IntPtr[] on each poll call.

#>

using namespace System.Net.Sockets

param (
    [Parameter(Mandatory=$true)]
    [string]$LocalIP,
    [Parameter(Mandatory=$true)]
    [UInt16]$LocalPort,
    [Parameter(Mandatory=$true)]
    [string]$RemoteIP,
    [Parameter(Mandatory=$true)]
    [UInt16]$RemotePort,
    [Parameter(Mandatory=$false)]
    [int]$TMOUTus = 100 * 1000 # MICROSECONDS
)

$LSocket = [System.Net.Sockets.Socket]::new(
           [System.Net.Sockets.SocketType]::Stream,
           [System.Net.Sockets.ProtocolType]::Tcp
)


$HostIP = [System.Net.Dns]::resolve($LocalIP).AddressList[0]
$LocalEndPoint = [System.Net.IPEndPoint]::new($HostIP, $LocalPort)

try {
    $remoteIp = [System.Net.IPAddress]::Parse($RemoteIP).Address
} catch {
    # Write-Output "Remote is not an IP ({[$($_.Exception.Message)]}). Trying to resolve $RemoteIP with DNS..."
    $remoteIp = [System.Net.Dns]::resolve($RemoteIP).AddressList[0].Address
}

$remoteEndpoint = [System.Net.IPEndPoint]::new($remoteIp, $RemotePort)

[byte[]]$LBuffer = [byte[]]::new($LSocket.ReceiveBufferSize)
[byte[]]$RBuffer = [byte[]]::new($LSocket.ReceiveBufferSize)

# TODO: Control socket timeouts System.Management.Automation.Runspaces.RunspaceFactory
# static [initialsessionstate] CreateDefault()
[PSCustomObject[]]$threads = [PSCustomObject[]]@()
$MaxThreads = 69
[initialsessionstate]$RunspacePoolSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
[System.Management.Automation.Runspaces.RunspacePool]$rsp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxThreads, $RunspacePoolSessionState, $host)
$rsp.CleanupInterval = [System.TimeSpan]::FromSeconds([double]5.7) # 5/7 iykyk ;) (0.7142857142857143 but meh)
#$rsp.ThreadOptions [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread #TODO: Research this more
$rsp.Open()

try {
    try {
        $LSocket.Bind($LocalEndPoint)
        $LSocket.Listen(500)
    } catch {
        Write-Error "`nUnable to bind and listen to the specified IP and port $($LocalIP):$($LocalPort)!`n$($_.Exception.Message)`n"
        $_
        if ($LSocket.Connected) { $LSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
        $LSocket.Close()
        $rsp.Close()
        $rsp.Dispose()
        exit -1
    }

    while ($LSocket.IsBound) {
        # this **might** be faster than foreach because foreach grabs an enumerator??
        for ($i=0; $i -lt $threads.Length; $i++) {
            $thread = $threads[$i]
            if ($null -ne $thread) {
                # $PowershellHandlerObject.Streams.Debug
                # $PowershellHandlerObject.Streams.Error
                # $PowershellHandlerObject.Streams.Information
                # $PowershellHandlerObject.Streams.Progress
                # $PowershellHandlerObject.Streams.Verbose
                # $PowershellHandlerObject.Streams.Warning
                if ($thread.PSHandle.IsCompleted) {
                    $thread.PSInstance.EndInvoke($thread.PSHandle)
                    $thread.PSInstance.Dispose()
                    $threads[$i] = $null
                }
            }
        }
# TODO: check if the array was made dirty and do this conditionally:
        $threads = $threads | Where-Object { $null -ne $_ }

        if (-not ($LSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectRead))) {
            continue # Continue waiting for an inbound connection! reeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
        }

        [System.Net.Sockets.Socket]$LCASocket = $LSocket.Accept() # $LCASocket means Local Connection Accepted Socket
        Write-Host "got connection :) from $($LCASocket.RemoteEndPoint)"

        # TODO: new thread can start here.
        # Invoke-Command -ArgumentList @(LCASocket, remoteEndpoint, $LBuffer, $RBuffer) -ScriptBlock {
        #Start-Job -ArgumentList @[System.Net.Sockets.Socket]$LCASocket, [System.Net.IPEndPoint]$remoteEndpoint, [byte[]]$LBuffer, [byte[]]$RBuffer -ScriptBlock {

        $ConnectionHandler = [System.Management.Automation.ScriptBlock]::Create({
            # param (
            #     [System.Net.Sockets.Socket]$LCASocket,
            #     [System.Net.IPEndPoint]$remoteEndpoint,
            #     [byte[]]$LBuffer,
            #     [byte[]]$RBuffer
            # )
            param (
                [PSCustomObject]$ConnArgs
            )
            # [System.Net.Sockets.Socket]$LCASocket = [System.Net.Sockets.Socket]$LCASocket
            # [System.Net.IPEndPoint]$remoteEndpoint = [System.Net.IPEndPoint]$remoteEndpoint

            [System.Net.Sockets.Socket]$LCASocket = [System.Net.Sockets.Socket]$ConnArgs["LCASocket"]
            [System.Net.IPEndPoint]$remoteEndpoint = [System.Net.IPEndPoint]$ConnArgs["remoteEndpoint"]
            [byte[]]$LBuffer = [byte[]]$ConnArgs["LBuffer"]
            [byte[]]$RBuffer = [byte[]]$ConnArgs["RBuffer"]
            [System.Management.Automation.PowerShell]$PSHandler = [System.Management.Automation.PowerShell]$ConnArgs["PSHandlerInstance"]

            if ($null -eq $LCASocket) {
                Write-Error "The incoming local connection socket is null. We cannot continue in handling this request!"
                return $false
            }

            Write-Host -NoNewLine "Connecting to remote socket... "
            try {
                # NOTE; THIS REMOTE SOCKET MUT BE REDECLARED BECAUSE IT CANNOT BE REUSED AFTER IT IS CLOSED AND IF WE ARE HERE IT IS EITHER FRESH OR HAS ALREADY BEEN CLOSED AT LEAST ONCE. (I tried re-using a remote socket and it did not work, need to do the allocation / instantiation here :-( )
                $RSocket = [System.Net.Sockets.Socket]::new(
                    [System.Net.Sockets.SocketType]::Stream,
                    [System.Net.Sockets.ProtocolType]::Tcp
                )
                $RSocket.Connect($remoteEndpoint)
                Write-Host "Established connection."
            } catch {
                Write-Host -NoNewLine -BackgroundColor Red "Error: $($_.Exception.Message)"
                $LCASocket.Shutdown([Systtem.Net.Sockets.SocketShutdown]::Both)
                $LCASocket.Close()
                Write-Host -BackgroundColor Black "Going back to listening..."
                continue # TODO: this continue statement needs to be converted to something else because it is not in a loop anymore, it is in a scriptblock in a thread.
            }

            if (-not ($RSocket.Connected)) {
                Write-Error "The server was depressed and didnt wanna talk to anybody . :("
                continue # TODO: see the todo above.
            }

            while ( $RSocket.Connected -and $LCASocket.Connected ) {
                #Write-Output "We are still connected to $($LCASocket.RemoteEndPoint)->$($LCASocket.LocalEndPoint):<->:$($RSocket.LocalEndPoint)->$($RSocket.RemoteEndPoint) :)"
                [UInt32]$totalShuffledBytes = [UInt32]0
                [UInt32]$bytesFromClinet    = [UInt32]0
                [UInt32]$bytesToServer      = [UInt32]0
                [UInt32]$bytesFromServer    = [UInt32]0
                [UInt32]$bytesToClient      = [UInt32]0

                [bool]$LocalCanRead = [bool]$LCASocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectRead)

                if ((-not ($LCASocket.Connected)) -or
                $LCASocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectError) -or
                (LocalCanRead -and $LCASocket.Available -eq 0)) {
                    Write-Error "Local socket has disconnected, or errored. Terminating connection..."
                    if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                    $RSocket.Close()
                    if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                    $LCASocket.Close()
                    break
                }

                if ($LocalCanRead -and $RSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectWrite)) { # TODO: apply boolean algebra rule to negate and turn into guard clause to reduce indentation.
                    # Write-Output "Grabbing data from inbound socket, and sending to outbound socket"
                    do {
                        try {
                            # Write-Output "Getting input data..."
                            [UInt32]$bytesFromClient = [UInt32]$LCASocket.Receive($LBuffer, [System.Net.Sockets.SocketFlags]::None)
                            # Write-Output "Got input data. $bytesFromClient bytes from client."
                        } catch {
                            Write-Error "ingress socket error: $($_.Exception.Message)"
                            $_
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        if ($bytesFromClient -eq 0) {
                            Write-Output "Client disconnected in poll for LCASocket  (R on ingress socket)"
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        try {
                            # Write-Output "Sending input data..."
                            [UInt32]$bytesToServer = [UInt32]$RSocket.Send($LBuffer, 0, $bytesFromClient, [System.Net.Sockets.SocketFlags]::None)
                            # Write-Output "Sent input data."
                        } catch {
                            Write-Error "outbound socket error: $($_.Exception.Message)"
                            $_
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        if ($bytesFromClient -ne $bytesToServer) {
                            Write-Error "Bytes from client ($bytesFromClient) does not match bytes to server ($bytesToServer)."
                        }

                        if ($bytesToServer -eq 0) {
                            Write-Output "Server disconnected in poll for RSocket (W on egress socket)"
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        $totalShuffledBytes += $bytesToServer
                    } while ( $bytesFromClient -gt 0 -and
                              $LCASocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectRead) -and
                              $RSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectWrite) )

                              # Write-Output "EXITED LCASOCKET POLL~~~~"

                    if ((-not $LCASocket.Connected) -or (-not $RSocket.Connected)) {
                        # Write-Output "We done goofed. Lets go back to listening for new connections."
                        break # TODO: see the todo above about being in a scriptblock.
                    }
                } #end checking local R -> remote W
                else {
                    # Write-Output "No data to move from local to remote socket."
                }
    # ^^ inbound TCP connection -> outbound TCP connection ^^
    ############################################################################################################
    # VV outbound TCP connection -> inbound TCP connection VV
                [bool]$RemoteCanRead = [bool]$RSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectRead)

                if ((-not ($RSocket.Connected)) -or $RSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectError) -or
                ($RemoteCanRead -and $RSocket.Available -eq 0)) {
                    Write-Error "Remote socket has disconnected, or errored. Terminating connection..."
                    if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                    $RSocket.Close()
                    if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                    $LCASocket.Close()
                    break
                }

                if ($RemoteCanRead -and $LCASocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectWrite))
                {
                    # Write-Output "Grabbing data from outbound socket, and sending to inbound socket"
                    do {
                        try {
                            # Write-Output "Getting data from remote"
                            [UInt32]$bytesFromServer = [UInt32]$RSocket.Receive($RBuffer, [System.Net.Sockets.SocketFlags]::None)
                            # Write-Output "**SLURPED**"
                        } catch {
                            Write-Error "General error grabbing data from remote socket: $($_.Exception.Message)"
                            $_
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        if ($bytesFromServer -eq 0) {
                            Write-Output "Server disconnected on RSocket poll (R on egress socket)"
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        try {
                            [UInt32]$bytesToClient = [UInt32]$LCASocket.Send($RBuffer, 0, $bytesFromServer, [System.Net.Sockets.SocketFlags]::None)
                        } catch {
                            Write-Error "Error sending remote data to local socket: $($_.Exception.Message)"
                            break
                        }

                        if ($bytesFromServer -ne $bytesToClient) {
                            Write-Error "Bytes from server ($bytesFromServer) does not match bytes to client ($bytesToClient)."
                        }

                        if ($bytesToClient -eq 0) {
                            Write-Output "Client disconnected in poll for RSocket (W on ingress socket)"
                            if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $RSocket.Close()
                            if ($LCASocket.Connected) { $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
                            $LCASocket.Close()
                            break
                        }

                        $totalShuffledBytes += $bytesToServer
                    } while ( $bytesFromClient -gt 0 -and
                                $RSocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectRead) -and
                                $LCASocket.Poll($TMOUTus, [System.Net.Sockets.SelectMode]::SelectWrite) )

                    # Write-Output "EXITED RSOCKET POLL"

                    if ((-not $LCASocket.Connected) -or (-not $RSocket.Connected)) {
                        # Write-Output "We done goofed after RSOCKET poll. Lets go back to listening for new connections."
                        break
                    }
                } #end checking for being able to read from and write to remote socket R -> local socket W
                else {
                    # Write-Output "No data to move from remote to local socket."
                }

                if ($totalShuffledBytes -eq 0) {
                    # Write-Output "No data transferred... sleeping."
                    Start-Sleep -Milliseconds ($TMOUTus / 1000)
                }
            } # end of $RSocket.Connected and $LCASocket.Connected while loop.

            # Write-Output 'end of $RSocket.Connected and $LCASocket.Connected while loop'
            if ($LCASocket.Connected) {
                $LCASocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both)
            }

            if ($RSocket.Connected) {
                $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both)
            }

            $RSocket.Close()
            # $PSHandler.EndInvoke($true) # TODO: What do we do in order to properly exit thread?
        }) # End of invoking command

        [System.Management.Automation.PowerShell]$PowershellHandlerObject = [System.Management.Automation.PowerShell]::Create()
        $PowershellHandlerObject.RunspacePool = $rsp
        $ConnectionArguments = @{
            LCASocket = [System.Net.Sockets.Socket]$LCASocket
            remoteEndpoint = [System.Net.IPEndPoint]$remoteEndpoint
            LBuffer = [byte[]]$LBuffer
            RBuffer = [byte[]]$RBuffer
            PSHandlerInstance = [System.Management.Automation.PowerShell]$PowershellHandlerObject
        }
        $PowershellHandlerObject.AddScript($ConnectionHandler).AddArgument($ConnectionArguments) | Out-Null

        $threads += [PSCustomObject]@{
            PSInstance = $PowershellHandlerObject
            PSHandle = $PowershellHandlerObject.BeginInvoke()
        }

        Write-Output "Threads left: $($rsp.GetAvailableRunspaces())"
# TODO: handle endinvoke somehow
    } # End of socket.isbound while loop.
} catch {
    Write-Error "General error in processing: $($_.Exception.Message)"
    $_
} finally {
    if ($RSocket.Connected) { $RSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
    $RSocket.Close()
    if ($LSocket.Connected) { $LSocket.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
    $LSocket.Close()
    $rsp.Close()
    $rsp.Dispose()
}


