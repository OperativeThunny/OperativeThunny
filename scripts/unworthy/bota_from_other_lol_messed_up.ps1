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

function assert {
    [CmdletBinding()]
    param(
        $cond,
        [string]$msg
    )

    if ($false -ne $cond) {
        Write-Error "Assertion failed."
        Write-Error $msg
        exit 1
    }
}

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
    
    $outputAdjustmentOffset = 33 # This is the amount to add to the value after converting the base aka radix to 85 to get a byte value in the ascii range of printable characters.
    
    # TODO: Uncomment this line and remove the test input line below
    #$inbytes = [System.IO.File]::ReadAllBytes($InputFile)
    [byte[]]$current5 = [byte[]]::CreateInstance([byte], 5)

    $OutputFile = "testingbtoa.txt"
    $testInput = "Man is distinguished, not only by his reason, but by this singular passion from other animals, which is a lust of the mind, that by a perseverance of delight in the continued and indefatigable generation of knowledge, exceeds the short vehemence of any carnal pleasure."
    # Testing string to match wiki
    $inbytes = $testInput.ToCharArray() | ForEach-Object { [byte]$_ }
    $expectedOutput = @"
9jqo^BlbD-BleB1DJ+*+F(f,q/0JhKF<GL>Cj@.4Gp`$d7F!,L7@<6@)/0JDEF<G%<+EV:2F!,O<DJ+*.@<*K0@<6L(Df-\0Ec5e;DffZ(EZee.Bl.9pF""AGXBPCsi+DGm>@3BB/F*&OCAfu2/AKYi(DIb:@FD,*)+C]UER(..I9)<Ff2M7/c
"@
    
    # Pad the input bytes to a multiple of 4
    if ($inbytes.Length % 4 -ne 0) {
        $inbytes = $inbytes + [byte[]]::CreateInstance([byte], 4 - ($inbytes.Length % 4))
    }

    $inbytes.Length
    $outsb = [System.Text.StringBuilder]::new($inbytes.Length)
    
    for ($i = 0; $i -lt $inbytes.Length; $i += 4) {
        $chunk = $inbytes[$i..($i+3)]
        # Do we need to reverse this to process the bytes as big endian? No, we do not. We could process everything in place with clever math and bit shifting. But, this is easier to understand.
        [Array]::Reverse($chunk) # No, we do not need to reverse it! # Yes, we do!
        [int32]$integerFromBytes = [System.BitConverter]::ToInt32($chunk, 0)
        $integerFromBytes
        if ($integerFromBytes -eq 0) {
            $outsb.Append('z')
            continue
        }
        
        $j = 0
        $k = 4 # too bad powershell cant do for loops with multiple initializers and incrementers
        do {
            #$integerFromBytes % 85
            $current5[$k] = [byte](($integerFromBytes % 85) + $outputAdjustmentOffset)
            #[byte](($integerFromBytes % 85) + $outputAdjustmentOffset)
            $integerFromBytes = [math]::Floor($integerFromBytes / 85)
            $j++
            $k--
        } while ($j -lt 5)

        assert($integerFromBytes -eq 0, "Erronious situation detected. we are left with more than 0 after converting to radix 85.")
        [System.Text.Encoding]::ASCII.GetString($current5)
        #Write-Error "test"
        $outsb.Append($current5, 0, 5)
        #Write-Output $outsb.ToString(0, $outsb.Length)
        #Write-Error "test2"
        [System.Console]::Out.Flush()
        # no output after appending to the stringbuilder :'(
        
        if ($chunk.Length -gt 5) {
            Write-Error "Erronious situation detected. Output block is too large."
            exit
        }
    }

    #$outbytes = [System.Text.Encoding]::ASCII.GetBytes($outsb.ToString(0, $outsb.Length))

    #[System.IO.File]::WriteAllBytes($OutputFile, $outbytes)



    # 1. READ INPUT FILE AS BYTE ARRAY
    # 2. CONVERT INPUT BYTE ARRAY TO BASE85
    # 3. WRITE CONVERTED DATA TO OUTPUT FILE
    # 4. RE-WRITE THE CODE TO DO EVERYTHING EVERYWHERE ALL AT ONCE (USE STREAMS AND READ/PROCESS/WRITE ALL AT THE SAME TIME SO IT HANDLES MULTIGIG FILES)
    # 5. HANDLE PARALLEL PROCESSING PIPELINES TODO: Write script for generically splitting up a giant set of input files for map/reduce ops.

}

btoa @args
