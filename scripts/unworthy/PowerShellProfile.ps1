# * @license Affero General Public License v3.0 (AGPL-3.0) https://opensource.org/licenses/AGPL-3.0 / https://www.gnu.org/licenses/agpl-3.0.en.html
# %USERPROFILE%\Documents\WindowsPowerShell\Microsoft.VSCode_profile.ps1
# TODO: code to convert ENV:\ entries to percent vars.
Write-Host -BackgroundColor Green "User local PowerShell Profile"

function ConvertTo-FileUri {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path
    )
    ([system.uri](Get-Item $Path).FullName).AbsoluteUri
}

New-Alias which get-command

$env:PATH += ';C:\Program Files\VSCode\bin\'
