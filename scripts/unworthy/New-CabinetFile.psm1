# FROM: https://gist.github.com/rheid/c00a3b18ba35aabaecf0
<#
.SYNOPSIS
    Creates a new cabinet .CAB file on disk.

.DESCRIPTION
    This cmdlet creates a new cabinet .CAB file using MAKECAB.EXE and adds
    all the files specified to the cabinet file itself.

.PARAMETER Name
    The output file name of the cabinet .CAB file, such as MyNewCabinet.cab.
    This should not be the entire file path, only the target file name.

.PARAMETER File
    One or more file references that are to be added to the cabinet .CAB file.
    FileInfo objects (as generated by Get-Item etc) or strings can be passed
    in via the pipeline to be added to the cabinet file.

.PARAMETER DestinationPath
    The output file path that the cabinet file will be saved in. It is also
    used for resolving any ambiguous file references, i.e. any file passed in
    via file name and not full path.

    If not specified the current working directory is used for the output file
    and attempting to resolve all ambiguous file references.

.PARAMETER NoClobber
    Will not overwrite of an existing file. By default, if a file exists in the
    specified path, New-CabinetFile overwrites the file without warning.

.EXAMPLE
    New-CabinetFile -Name MyCabinet.cab -File "File01.exe","File02.txt"

    This creates a new MyCabinet.cab file in the current directory and adds the File01.exe and File02.txt files to it, also from the current directory.
.EXAMPLE
    Get-ChildItem C:\CabFile\ | New-CabinetFile -Name MyCabinet.cab -DestinationPath C:\Users\UserA\Documents

    This creates a new C:\Users\UserA\Documents\MyCabinet.cab file and adds all files within the C:\CabFile\ directory into it.
#>
function New-CabinetFile {
    [CmdletBinding()]
    Param(
        [Parameter(HelpMessage="Target .CAB file name.", Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("FilePath")]
        [string] $Name,

        [Parameter(HelpMessage="File(s) to add to the .CAB.", Position=1, Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("FullName")]
        [string[]] $File,

        [Parameter(HelpMessage="Default intput/output path.", Position=2, ValueFromPipelineByPropertyName=$true)]
        [AllowNull()]
        [string[]] $DestinationPath,

        [Parameter(HelpMessage="Do not overwrite any existing .cab file.")]
        [Switch] $NoClobber
        )

    Begin {

        ## If $DestinationPath is blank, use the current directory by default
        if ($DestinationPath -eq $null) { $DestinationPath = (Get-Location).Path; }
        Write-Verbose "New-CabinetFile using default path '$DestinationPath'.";
        Write-Verbose "Creating target cabinet file '$(Join-Path $DestinationPath $Name)'.";

        ## Test the -NoClobber switch
        if ($NoClobber) {
            ## If file already exists then throw a terminating error
            if (Test-Path -Path (Join-Path $DestinationPath $Name)) { throw "Output file '$(Join-Path $DestinationPath $Name)' already exists."; }
        }

        ## Cab files require a directive file, see 'http://msdn.microsoft.com/en-us/library/bb417343.aspx#dir_file_syntax' for more info
        $ddf = ";*** MakeCAB Directive file`r`n";
        $ddf += ";`r`n";
        $ddf += ".OPTION EXPLICIT`r`n";
        $ddf += ".Set CabinetNameTemplate=$Name`r`n";
        $ddf += ".Set DiskDirectory1=$DestinationPath`r`n";
        $ddf += ".Set MaxDiskSize=0`r`n";
        $ddf += ".Set Cabinet=on`r`n";
        $ddf += ".Set Compress=on`r`n";
        ## Redirect the auto-generated Setup.rpt and Setup.inf files to the temp directory
        $ddf += ".Set RptFileName=$(Join-Path $ENV:TEMP "setup.rpt")`r`n";
        $ddf += ".Set InfFileName=$(Join-Path $ENV:TEMP "setup.inf")`r`n";

        ## If -Verbose, echo the directive file
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            foreach ($ddfLine in $ddf -split [Environment]::NewLine) {
                Write-Verbose $ddfLine;
            }
        }
    }

    Process {

        ## Enumerate all the files add to the cabinet directive file
        foreach ($fileToAdd in $File) {

            ## Test whether the file is valid as given and is not a directory
            if (Test-Path $fileToAdd -PathType Leaf) {
                Write-Verbose """$fileToAdd""";
                $ddf += """$fileToAdd""`r`n";
            }
            ## If not, try joining the $File with the (default) $DestinationPath
            elseif (Test-Path (Join-Path $DestinationPath $fileToAdd) -PathType Leaf) {
                Write-Verbose """$(Join-Path $DestinationPath $fileToAdd)""";
                $ddf += """$(Join-Path $DestinationPath $fileToAdd)""`r`n";
            }
            else { Write-Warning "File '$fileToAdd' is an invalid file or container object and has been ignored."; }
        }
    }

    End {

        $ddfFile = Join-Path $DestinationPath "$Name.ddf";
        $ddf | Out-File $ddfFile -Encoding ascii | Out-Null;

        Write-Verbose "Launching 'MakeCab /f ""$ddfFile""'.";
        $makeCab = Invoke-Expression "MakeCab /F ""$ddfFile""";

        ## If Verbose, echo the MakeCab response/output
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            ## Recreate the output as Verbose output
            foreach ($line in $makeCab -split [environment]::NewLine) {
                if ($line.Contains("ERROR:")) { throw $line; }
                else { Write-Verbose $line; }
            }
        }

        ## Delete the temporary .ddf file
        Write-Verbose "Deleting the directive file '$ddfFile'.";
        Remove-Item $ddfFile;

        ## Return the newly created .CAB FileInfo object to the pipeline
        Get-Item (Join-Path $DestinationPath $Name);
    }
}

Export-ModuleMember -Function * -Cmdlet * -Variable * -Alias *
