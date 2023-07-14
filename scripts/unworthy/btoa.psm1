#!/usr/bin/env pwsh
<#
.SYNOPSIS
    btoa - Base85 encode a file. This is a powershell implementation of the btoa utility. It is not a drop in replacement for the btoa utility.
    Also known as ascii85 encoding.
    base64 is for lusers. base85 is for chads.
.DESCRIPTION
    It takes bytes and interprets each set of 4 bytes as a single 32 bit base85 integer, then it converts that to a base85 string consuming 5 bytes. The output is a string of ascii characters.
    base64 inflates data by 33% and base85 inflates data by 25%. base85 is more efficient than base64.
    This differs from uuencode in that it does not use a 6 bit encoding scheme. It uses a 32 bit encoding scheme.

    Taken from the wikipedia page:

      When encoding, each group of 4 bytes is taken as a 32-bit binary
      number, most significant byte first (Ascii85 uses a big-endian
      convention). This is converted, by repeatedly dividing by 85 and
      taking the remainder, into 5 radix-85 digits. Then each digit (again,
      most significant first) is encoded as an ASCII printable character by
      adding 33 to it, giving the ASCII characters 33 (!) through 117 (u).

      Because all-zero data is quite common, an exception is made for the
      sake of data compression, and an all-zero group is encoded as a single
      character z instead of !!!!!.

      Groups of characters that decode to a value greater than 232 − 1
      (encoded as s8W-!) will cause a decoding error, as will z characters
      in the middle of a group. White space between the characters is
      ignored and may occur anywhere to accommodate line-length limitations.
      Limitations

      The original specification only allows a stream that is a multiple of
      4 bytes to be encoded.

      Encoded data may contain characters that have special meaning in many
      programming languages and in some text-based protocols, such as
      left-angle-bracket <, backslash \, and the single and double quotes '
      & ". Other base-85 encodings like Z85 and RFC 1924 are designed to be
      safe in source code.[4]
.NOTES
    https://en.wikipedia.org/wiki/Ascii85
.LINK
    TODO: more verbose help for the verboten?
.EXAMPLE
    btoa -InputFile "C:\Users\user\Downloads\test.txt" -OutputFile "C:\Users\user\Downloads\test.btoa.b85.txt"
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

    #$inbytes = [System.IO.File]::ReadAllBytes($InputFile)
    #[byte[]]$current5 = [byte[]]::CreateInstance([byte], 5)

    $OutputFile = "testingbtoa.txt"
    $testInput = "Man is distinguished, not only by his reason, but by this singular passion from other animals, which is a lust of the mind, that by a perseverance of delight in the continued and indefatigable generation of knowledge, exceeds the short vehemence of any carnal pleasure."
    # Testing string to match wiki
    $inbytes = $testInput.ToCharArray() | ForEach-Object { [byte]$_ }

$expectedOutput = "
9jqo^BlbD-BleB1DJ+*+F(f,q/0JhKF<GL>Cj@.4Gp`$d7F!,L7@<6@)/0JDEF<G%<+EV:2F!,O<
DJ+*.@<*K0@<6L(Df-\0Ec5e;DffZ(EZee.Bl.9pF`"AGXBPCsi+DGm>@3BB/F*&OCAfu2/AKYi(
DIb:@FD,*)+C]U=@3BN#EcYf8ATD3s@q?d`$AftVqCh[NqF<G:8+EV:.+Cf>-FD5W8ARlolDIal(
DId<j@<?3r@:F%a+D58'ATD4`$Bl@l3De:,-DJs``8ARoFb/0JMK@qB4^F!,R<AKZ&-DfTqBG%G>u
D.RTpAKYo'+CT/5+Cei#DII?(E,9)oF*2M7/c" -replace "`n", "" -replace "`r", ""

    # Pad the input bytes to a multiple of 4
    $padding = 0
    if ($inbytes.Length % 4 -ne 0) {
        $inbytes = $inbytes + [byte[]]::CreateInstance([byte], 4 - ($inbytes.Length % 4))
        $padding = 4 - ($inbytes.Length % 4)
    }

    $outputBytes = [byte[]]::CreateInstance([byte], (($inbytes.Length * 5)/4) )
    $bigChunkus = 0

    for ($i = 0; $i -lt $inbytes.Length; $i += 4) {
        $chunk = $inbytes[$i..($i+3)]
        # Do we need to reverse this to process the bytes as big endian? No, we do not. We could process everything in place with clever math and bit shifting. But, this is easier to understand.
        [Array]::Reverse($chunk) # No, we do not need to reverse it! # Yes, we do!
        [int32]$integerFromBytes = [System.BitConverter]::ToInt32($chunk, 0)
        #$integerFromBytes
        if ($integerFromBytes -eq 0) {
            $outputBytes[$bigChunkus] = [byte]('z')
            continue
        }

        $j = 0
        $k = 4 # too bad powershell cant do for loops with multiple initializers and incrementers
        do {
            #$integerFromBytes % 85
            #$current5[$k] = [byte](($integerFromBytes % 85) + $outputAdjustmentOffset)
            $outputBytes[$bigChunkus + $k] = [byte](($integerFromBytes % 85) + $outputAdjustmentOffset)
            #[byte](($integerFromBytes % 85) + $outputAdjustmentOffset)
            $integerFromBytes = [math]::Floor($integerFromBytes / 85)
            $j++
            $k--
        } while ($j -lt 5)
        $bigChunkus += 5

        assert($integerFromBytes -eq 0, "Erronious situation detected. we are left with more than 0 after converting to radix 85.")
        #[System.Text.Encoding]::ASCII.GetString($current5)
    }

    echo "We have exited the encoding loop."
    #$outputBytes | Format-Hex # Todo: figure out how to use the console to show the hex output change over time live instead outputting it over and over again.
    $EncodedString = [System.Text.Encoding]::ASCII.GetString($outputBytes, 0, ($outputBytes.Length - $padding) + 1)
    $EncodedString | Format-Hex
    $expectedOutput | Format-Hex
    $EncodedString
    $expectedOutput 
    $EncodedString.Length
    $expectedOutput.Length

    [System.Text.Encoding]::ASCII.GetString([System.Convert]::GetBytes($expectedOutput))
    
    assert($expectedOutput.Equals($EncodedString), "Expected output does not match actual output.")
    #$outbytes = [System.Text.Encoding]::ASCII.GetBytes($outsb.ToString())

    $OutFileHandle = [System.IO.File]::OpenWrite($OutputFile)
    $OutFileHandle.Write($outputBytes, 0, $outputBytes.Length - $padding)
    $OutFileHandle.Close()

    #[System.Text.Encoding]::

    # 1. READ INPUT FILE AS BYTE ARRAY
    # 2. CONVERT INPUT BYTE ARRAY TO BASE85
    # 3. WRITE CONVERTED DATA TO OUTPUT FILE
    # 4. RE-WRITE THE CODE TO DO EVERYTHING EVERYWHERE ALL AT ONCE (USE STREAMS AND READ/PROCESS/WRITE ALL AT THE SAME TIME SO IT HANDLES MULTIGIG FILES)
    # 5. HANDLE PARALLEL PROCESSING PIPELINES TODO: Write script for generically splitting up a giant set of input files for map/reduce ops.

}

btoa @args
