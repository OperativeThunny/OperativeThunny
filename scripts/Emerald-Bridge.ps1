#!/usr/bin/env pwsh
<#
Emerald-Bridge.ps1
This is a stream socket layer TCP bridge that binds to specified ip and port and connects to specified remote IP endpoint and forwards traffic between the two.
Like a simpler netcat.
Idk if windows STDIN and STDOUT will be redirectable to a socket like on linux, but we'll give 'er the ol' college try.
Author: @OperativeThunny ( bluesky @verboten.zip )
Date: 20230714
Copyright (C) 2023 Operative Thunny. All rights reserved.
Eventually a license will be decided upon, but for now all rights reserved.
#>

# Step 1: Parse arguments
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$LocalIP,
    [Parameter(Mandatory=$true)]
    [int]$LocalPort,
    [Parameter(Mandatory=$true)]
    [string]$RemoteIP,
    [Parameter(Mandatory=$true)]
    [int]$RemotePort
)

# Step 2: Create a socket
$socket = [System.Net.Sockets.Socket]::new(
    [System.Net.Sockets.AddressFamily]::InterNetwork, 
    [System.Net.Sockets.SocketType]::Stream, 
    [System.Net.Sockets.ProtocolType]::Tcp
)

# Step 3: Bind the socket to the local IP and port
$socket.Bind([System.Net.IPEndPoint]::new(
    [System.Net.IPAddress]::Parse($LocalIP), 
    $LocalPort
))

# Step 4: Connect the socket to the remote IP and port
$socket.Connect([System.Net.IPEndPoint]::new(
    [System.Net.IPAddress]::Parse($RemoteIP), 
    $RemotePort
))

# Step 5: Create a buffer to hold data
$buffer = [byte[]]::new(1024)

# Step 6: Create a loop to read data from the socket and write it to STDOUT
while ($true) {
    $bytesRead = $socket.Receive($buffer)
    if ($bytesRead -eq 0) {
        break
    }
    [Console]::OpenStandardOutput().Write($buffer, 0, $bytesRead)
}

# Step 7: Close the socket
$socket.Close()


