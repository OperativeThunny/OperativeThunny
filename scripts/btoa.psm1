#!/usr/bin/env pwsh
<#
.SYNOPSIS
    A short one-line action-based description, e.g. 'Tests if a function is valid'
.DESCRIPTION
    A longer description of the function, its purpose, common use cases, etc.
.NOTES
    https://en.wikipedia.org/wiki/Ascii85
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    Test-MyTestFunction -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>
function btoa {
    param (
        [Parameter(HelpMessage="Target file name to encode.", Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_})]
        [Alias("FilePath")]
        [string]$InputFile,

        [Parameter(HelpMessage="Encoded output file.", Position=1, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("OutputPath")]
        [string]$OutputFile
    )
    
    $inbytes = [System.IO.File]::ReadAllBytes($InputFile)

    for ($i = 0; $i -lt $inbytes.Length; $i += 4) {
        $chunk = $inbytes[$i..($i+3)]
        [Console]::WriteLine("{0,30}", $([System.BitConverter]::ToString($chunk)) )
        $chunk = [System.BitConverter]::ToInt32($chunk, 0)
        [Console]::WriteLine("{0,30}", $([System.BitConverter]::ToString( [System.BitConverter]::GetBytes($chunk))) )
        echo $chunk
        $chunk = [System.BitConverter]::GetBytes($chunk)
        [Array]::Reverse($chunk)
        [Console]::WriteLine("{0,30}", $([System.BitConverter]::ToString($chunk)) )
        $chunk = [System.BitConverter]::ToInt32($chunk, 0)
        [Console]::WriteLine("{0,30}", $([System.BitConverter]::ToString( [System.BitConverter]::GetBytes($chunk))) )
        #$chunk = [System.BitConverter]::
        echo $chunk
        exit
        $chunk = [System.BitConverter]::GetBytes($chunk)
        $chunk = $chunk[0..3]
        $chunk = [System.Convert]::ToBase64String($chunk)
        
        $chunk = $chunk -replace '[=]', ''
        $chunk = $chunk -replace '[+]', '-'
        $chunk = $chunk -replace '[/]', '_'
        $chunk = $chunk -replace '[\r\n]', ''
        $chunk = $chunk -replace '[\s]', ''
        $chunk = $chunk -replace '[\t]', ''
        $chunk = $chunk -replace '[\f]', ''
        $chunk = $chunk -replace '[\v]', ''
        $chunk = $chunk -replace '[\b]', ''
        $chunk = $chunk -replace '[\a]', ''
        $chunk = $chunk -replace '[\e]', ''
        $chunk = $chunk -replace '[\0]', ''
        $chunk = $chunk -replace '[\n]', ''
        $chunk = $chunk -replace '[\r]', ''
    }

    $outbytes = [System.Text.Encoding]::ASCII.GetBytes($inbytes)



    # 1. READ INPUT FILE AS BYTE ARRAY
    # 2. CONVERT INPUT BYTE ARRAY TO BASE85
    # 3. WRITE CONVERTED DATA TO OUTPUT FILE
    # 4. RE-WRITE THE CODE TO DO EVERYTHING EVERYWHERE ALL AT ONCE (USE STREAMS AND READ/PROCESS/WRITE ALL AT THE SAME TIME SO IT HANDLES MULTIGIG FILES)
    # 5. HANDLE PARALLEL PROCESSING PIPELINES TODO: Write script for generically splitting up a giant set of input files for map/reduce ops.

}



btoa @args
