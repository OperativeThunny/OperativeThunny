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
        [System.IO.Path]$InputFile,
        [System.IO.Path]$OutputFile
    )

    # 1. READ INPUT FILE AS BYTE ARRAY
    # 2. CONVERT INPUT BYTE ARRAY TO BASE85
    # 3. WRITE CONVERTED DATA TO OUTPUT FILE
    # 4. RE-WRITE THE CODE TO DO EVERYTHING EVERYWHERE ALL AT ONCE (USE STREAMS AND READ/PROCESS/WRITE ALL AT THE SAME TIME SO IT HANDLES MULTIGIG FILES)
    # 5. HANDLE PARALLEL PROCESSING PIPELINES TODO: Write script for generically splitting up a giant set of input files for map/reduce ops.
}

