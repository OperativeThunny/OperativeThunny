#!/usr/bin/env pwsh
<#
Emerald-Bridge.ps1
This is a stream socket layer TCP bridge that binds to specified ip and port and connects to specified remote IP endpoint and forwards traffic between the two.
Like a simpler netcat.
Idk if windows STDIN and STDOUT will be redirectable to a socket like on linux, but we'll give 'er the ol' college try.
Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230714
Copyright (C) 2023 Operative Thunny.
Copyright (C) 2023 Operative Thunny. All rights reserved. Eventually a license
will be decided upon, but for now all rights reserved.
#>

# Step 1: Parse arguments
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$LocalIP,
    [Parameter(Mandatory=$true)]
    [UInt16]$LocalPort,
    [Parameter(Mandatory=$true)]
    [string]$RemoteIP,
    [Parameter(Mandatory=$true)]
    [UInt16]$RemotePort
)

$Global:M_HAROLD_DEBUG = $true

# cmdlet to copy one stream to another using a buffer:
function Copy-Stream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [System.IO.Stream]$Source,
        [Parameter(Mandatory=$true, Position=1)]
        [System.IO.Stream]$Destination,
        [Parameter(Mandatory=$false, Position=2)]
        [UInt32]$BufferSize,
        [Parameter(Mandatory=$false, Position=3)]
        [byte[]]$Buffer
    )
# TODO: if buffer unspecified, use stdio
# [Console]::OpenStandardOutput().Write($buffer, 0, $bytesRead)
    if ($null -eq $Buffer) {
        if ($null -eq $BufferSize) {
            $BufferSize = 65536
        }
        $Buffer = [byte[]]::new($BufferSize)
    } else {
        $BufferSize = $Buffer.Length
    }

    [UInt32]$read = 0 # I wonder if it will be a problem using an unsigned int here, the docs just say int which is signed so I'm not sure if it will be a problem or not. if it is then this could be a big booboo.
    while ( ($read = $Source.Read($Buffer, 0, $BufferSize)) -gt 0 ) {
        Write-Output "Read $read bytes from stream: $([System.Text.Encoding]::UTF8.GetString($Buffer, 0, $read))"
        Write-Output "Writing to destination..."
        $Destination.Write($Buffer, 0, $read)
        Write-Output "Wrote $read bytes to destination."
    }
}

# Step 2: Create a socket
$socket = [System.Net.Sockets.Socket]::new(
#    [System.Net.Sockets.AddressFamily]::InterNetwork, # Commented out to use a different constructor overload which resuls in different socket behavior as a side effect...
    [System.Net.Sockets.SocketType]::Stream,
    [System.Net.Sockets.ProtocolType]::Tcp
)

$HostIP = [System.Net.Dns]::resolve($LocalIP).AddressList[0]
$LocalEndpoint = [System.Net.IPEndPoint]::new($HostIP, $LocalPort)
# Step 3: Bind the socket to the local IP and port
try {
    $remoteIp = [System.Net.IPAddress]::Parse($RemoteIP).Address
} catch {
    $_
    Write-Output "Remote is not an IP. Trying to resolve $RemoteIP..."
    $remoteIp = [System.Net.Dns]::resolve($RemoteIP).AddressList[0].Address
}
$remoteEndpoint = [System.Net.IPEndPoint]::new($remoteIp, $RemotePort)
Write-Output "Remote socket:"
$remoteEndpoint

[byte[]]$localBuffer = [byte[]]::new($socket.ReceiveBufferSize)
[byte[]]$remoteBuffer = [byte[]]::new($socket.ReceiveBufferSize)

try {
    $socket.Bind($LocalEndpoint)
    $socket.Listen(500)
# TODO: Re-write this using System.Net.Sockets.Socket.Poll() instead of how it is now.
# TODO: Ignore that last TODO, re-write this using System.Net.Sockets.Socket.Select() because poll uses select under the hood in .net, and it also does a new IntPtr[] allocation each time you call it, causing more memory usage ( https://stackoverflow.com/questions/1249643/is-there-a-way-to-poll-a-socket-in-c-sharp-only-when-something-is-available-for/23737811#23737811 )
    while ($socket.IsBound) {
        $connectionSocket = $socket.Accept()

        #[System.Net.Sockets.NetworkStream]$localStream = [System.Net.Sockets.NetworkStream]::new($connectionSocket, $true)
        $remoteSocket = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.SocketType]::Stream,
            [System.Net.Sockets.ProtocolType]::Tcp
        )
        Write-Output "Connecting to remote socket..."
        $remoteSocket.Connect($remoteEndpoint)
        #[System.Net.Sockets.NetworkStream]$remoteStream = [System.Net.Sockets.NetworkStream]::new($remoteSocket, $true)

        if ($remoteSocket.Connected) {
            do {
                if ($connectionSocket.Available -gt 0) {
                    $bytesFromClient = $connectionSocket.Receive($localBuffer, 0, $localBuffer.Length, [System.Net.Sockets.SocketFlags]::None)
                    $bytesToServer = $remoteSocket.Send($localBuffer, 0, $bytesFromClient, [System.Net.Sockets.SocketFlags]::None)

                    if ($bytesFromClient -ne $bytesToServer) {
                        Write-Error "Bytes from client ($bytesFromClient) does not match bytes to server ($bytesToServer)."
                    }

                    if ($bytesFromClient -eq 0) {
                        Write-Output "Client disconnected."
                        break
                    }

                    if ($bytesToServer -eq 0) {
                        Write-Output "Server disconnected."
                        break
                    }

                    $Global:M_HAROLD_DEBUG && Write-Output "Read $bytesFromClient bytes from client and wrote $bytesToServer bytes to server."
                } else {
                    $Global:M_HAROLD_DEBUG && Write-Output "No data available from client."
                }

                $bytesFromServer = $remoteSocket.Receive($remoteBuffer, 0, $remoteBuffer.Length, [System.Net.Sockets.SocketFlags]::None)
                $bytesToClient = $connectionSocket.Send($remoteBuffer, 0, $bytesFromServer, [System.Net.Sockets.SocketFlags]::None)

                if ($bytesFromServer -ne $bytesToClient) {
                    Write-Error "Bytes from server ($bytesFromServer) does not match bytes to client ($bytesToClient)."
                }

                if ($bytesFromServer -eq 0) {
                    Write-Output "Server disconnected."
                    break
                }

                if ($bytesToClient -eq 0) {
                    Write-Output "Client disconnected."
                    break
                }

            } while ($remoteSocket.Connected -and $connectionSocket.Connected -and $bytesFromClient -gt 0 -and $bytesFromServer -gt 0)


            # while ($localStream.CanRead -and $remoteStream.CanWrite) {
            #     Write-Output "reading from inbound writing to outbound"
            #     Copy-Stream $localStream $remoteStream $localBuffer.Length $localBuffer
            #     Write-Output "flushing outbound"
            #     $remoteStream.Flush()
            #     Start-Sleep -Milliseconds 100
            #     Write-Output "Suffling server to client"
            #     Copy-Stream $remoteStream $localStream $remoteBuffer.Length $remoteBuffer
            #     write-Output "flushing inbound"
            #     $localStream.Flush()
            # }

            # $localStream.Close()
            # $remoteStream.Close()
            $connectionSocket.Close()
            $remoteSocket.Close()
        } else {
            try {
                $connectionSocket.Disconnect()
                $connectionSocket.Close()
                $socket.Close()
                break
            } catch {
                Write-Error "Something borked while handling the fact that the server was depressed and didn't wanna talk to anybody."
            }
        }
    }

    if ($remoteSocket.Connected) {
        $remoteSocket.Disconnect($false)
    }

    $socket.Close()

} catch {
    $_
    $remoteSocket.Close()
    $socket.Close()
}


