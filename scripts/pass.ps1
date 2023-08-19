#!/usr/bin/env pwsh
<#
file: pass.ps1

random password generator and local "password database" manager.

Requirements:
    powershell script that works with a default install of windows 10 with
      powershell 5.1 only and no options of installing newer .net core or
      powershell or windows terminal. We are stuck with .net FRAMEWORK 4.8.
    Uses hardware x.509 PKI smartcards to encrypt master key and sign encrypted
      DB.

#>
<#
.SYNOPSIS
.DESCRIPTION
.NOTES
.LINK
.EXAMPLE
#>
using namespace System.Security.Cryptography

param(
    [Parameter(Mandatory=$true,
               Position=0,
               HelpMessage="Operation to perform: new, generate, search, get, put, push, pop, export, import")]
    [ValidateSet("new", "generate", "search", "get", "put", "push", "pop", "export", "import")]
    [string]$Operation,

    # [Parameter(Mandatory=$false,
    #            Position=1)]
    # [PSCredential]
    # $Passphrase,

    [Parameter(Mandatory=$false,
               Position=1,
               #ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to encrypted password database.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $DatabaseFile = "./int0x80.bin",

    [Parameter(Mandatory=$false,
               Position=2)]
    [UInt64]
    $Length = 33,

    [Parameter(Mandatory=$false,
               Position=3)]
    [switch]
    $PromptForName = $false,

    [Parameter(Mandatory=$false,
               Position=4)]
    [string]
    $NewEntryName = $null,

    [Parameter(Mandatory=$false,
               Position=5)]
    [string]
    $NewEntryDescription = $null,

    [Parameter(Mandatory=$false,
               Position=6)]
    [UInt64]
    $KeyDerivationIterations = 100000
)

if ($KeyDerivationIterations -lt 1000) {
    Write-Error "Key derivatrion function iterations is less than 1k! This is not recommended!"
    if (!(Read-Host -Prompt "Do you want to continue. Enter 'yes' to continue, anything else to exit.").ToLower().Trim().Equals("yes")) {
        Write-Error "Exiting."
        exit -99
    }
}

<#
upper: 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90
numeric: 48 49 50 51 52 53 54 55 56 57
lower: 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122
specials: 126 33 64 35 36 37 94 38 42 40 41 95 43 45 61 123 125 124 91 93 92 58 34 59 39 60 62 63 44 46 47
#>

# $alphlower = "abcdefghijklmnopqrstuvwxyz"
# $alphupper = $alphlower.ToUpper().ToCharArray()
# $alphlower = $alphlower.ToCharArray()
# $num = (0..9) | %{ [char]"$_" }
# $specials = '~!@#$%^&*()_+-={}|[]\:";''<>?,./'
# $specials = $specials.ToCharArray()

# $NonCoolCharClasses = @{
#     lower = $alphlower
#     upper = $alphupper
#     numeric = $num
#     specials = $specials
# }

$AsciiCharacterClasses = [ordered]@{
    NUL = [char[]]@(0x00)
    #nonprintables = [char[]](0x01..0x1F)
    lowspecials = [char[]](0x20..0x2F)
    numerals = [char[]](0x30..0x39)
    lowmidspecials = [char[]](0x3A..0x40)
    upperalpha = [char[]](0x41..0x5A)
    highmidspecials = [char[]](0x5B..0x60)
    loweralpha = [char[]](0x61..0x7A)
    DEL = [char[]]@(0x7F)
    extendedwonky = [char[]](0x80..0xA0)
    extendedprintable = [char[]](0xA1..0xFE)
}

# ForEach ($k in $charClasses.Keys) {
#     "$($k): $($charClasses[$k] | %{ if ($_ -ne `"`") { [byte]([char]($_))} } )"
# }

# ForEach ($k in $AsciiCharacterClasses.Keys) {
#     "$($k): $($($AsciiCharacterClasses[$k] | %{ $([char]($_)) }) -join "','")"
# }

[char[]]$AllCharacterClasses =
  $AsciiCharacterClasses.lowspecials +
  $AsciiCharacterClasses.numerals +
  $AsciiCharacterClasses.lowmidspecials +
  $AsciiCharacterClasses.upperalpha +
  $AsciiCharacterClasses.highmidspecials +
  $AsciiCharacterClasses.loweralpha #+
  #$AsciiCharacterClasses.extendedprintable

#[byte[]]$full = $alphlower + $alphupper + $num + $specials
#$full | % { [byte]$_ }
#Get-Random -Count 32 -InputObject [char[]]($full)
#Get-Random -Count 32 -InputObject (65..90) | % -begin {$aa=$null} -process {$aa += [char]$_} -end {$aa}
#$randomPassword = (Get-Random -Count $Length -InputObject $AllCharacterClasses) -join ""

# Could be a simple one liner but since we are dealing with passwords, we should probably make sure it is generated in a cryptographically secure way:
[System.Security.Cryptography.RandomNumberGenerator]$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
[byte[]]$randomPasswordSeedBytes = [byte[]]::new($Length)
[byte[]]$randomPasswordSeedRegen = [byte[]]::new($Length)
[byte[]]$randomPasswordIndicies = [byte[]]::new($Length)
[char[]]$randomPasswordChars = [char[]]::new($Length)

$rng.GetBytes($randomPasswordSeedBytes, 0, $Length)
$alphabetLen = $AllCharacterClasses.Length
$totalRegens = 0

for ([int] $i = 0; $i -lt $Length; $i++) {
    $curRnd = $randomPasswordSeedBytes[$i]

    if ($curRnd -ge $alphabetLen) {
        #$randomPasswordIndicies[$i] = $curRnd % $alphabetLen # straight mod biases towards zero and bias is bad in cryptoland
        # $randomIndex = Get-Random -SetSeed $curRnd -Minimum 0 -Maximum $alphabetLen # I really dont know if this is any better than straight mod but according to this, straight mod is not cryptographically secure even used with a cryptographically secure input: https://crypto.stackexchange.com/questions/7996/correct-way-to-map-random-number-to-defined-range
        # $randomPasswordIndicies[$i] = $randomIndex
        # $randomPasswordChars[$i] = $AllCharacterClasses[$randomIndex]
        # Maybe this will be better, to keep regenerating a random buffer until a byte at our current index is less than the array bounds:
        $regenIterations = 0
        do {
            $rng.GetBytes($randomPasswordSeedRegen, 0, $randomPasswordSeedRegen.Length)
            $curRnd = $randomPasswordSeedRegen[$i]
            $regenIterations++
        } while ($curRnd -ge $alphabetLen) # What is the probability this loop is non-terminating, forever?

 #       Write-Debug "We had to regenerate random bytes $($regenIterations) times for index $($i)."
        $totalRegens += $regenIterations
    }
    $randomPasswordIndicies[$i] = $curRnd
    $randomPasswordChars[$i] = $AllCharacterClasses[$curRnd]
}
#Write-Debug "We had to regenerate random bytes $($totalRegens) times for this password!"
$randomPassword = [string]::new($randomPasswordChars)

if ($Operation -eq "generate") {
    # generate simply generates a new random string and does nothing else. "new" does more.
    # $randomPasswordSeedBytes.Length
    # $randomPasswordSeedBytes -join ","
    # $randomPasswordIndicies.Length
    # $randomPasswordIndicies -join ","
    # $AllCharacterClasses -join ""
    # $randomPasswordChars.Length
    # $randomPasswordChars -join ","
    $randomPassword
    exit 0
}

Write-Host -BackgroundColor Green "The generated password is {{{{$randomPassword}}}}"

if ($PromptForName) {
    $pwname = Read-Host -Prompt "What would you like to name this password?"
    if ($null -eq $NewEntryDescription) {
        $NewEntryDescription = Read-Host -Prompt "What would you like to add to the encrypted description for this password?`n`n"
    }
} else {
    $pwname = $NewEntryName

    if ($null -eq $NewEntryName) {
        Write-Debug "No entry name specified and no prompt specified, defaulting to a guid."
        $pwname = New-Guid
    }
}
<#
$passwordEntry = [ordered]@{
    sequence = 0
    id = New-Guid
    name = $pwname
    password = $randomPassword
    secure_note = $NewEntryDescription
}
#>

class PasswordEntry {
    [string]$sequence
    [string]$id
    [string]$name
    [string]$password
    [string]$secure_note

    PasswordEntry() {
        $this.sequence = 0
        $this.id = New-Guid
        $this.name = New-Guid
        $this.password = ""
        $this.secure_note = ""
    }

    PasswordEntry([string]$sequence, [string]$id, [string]$name, [string]$password, [string]$secure_note) {
        $this.sequence = $sequence
        $this.id = if ($null -eq $id) { New-Guid } else { $id }
        $this.name = if ($null -eq $name) { New-Guid } else { $name }
        $this.password = $password
        $this.secure_note = $secure_note
    }
}

class PasswordDatabase {
    [byte[]]$MasterKey
    [byte[]]$MasterSalt
    [byte[]]$DerivedMasterKey
    [System.Collections.Generic.Dictionary[string, PasswordEntry]]$Entries
    [byte[]]$EncryptedEntries
}

$passwordEntry = [PasswordEntry]::new(0, $null, $pwname, $randomPassword, $NewEntryDescription)



if(!(Test-Path $DatabaseFile)) {
    [byte[]]$ppbytes = [byte[]]::new(32)
    [byte[]]$ppsalt = [System.Byte[]]::new(32)
    $rng.GetBytes($ppsalt, 0, $ppsalt.Length)
    $rng.GetBytes($ppbytes, 0, $ppbytes.Length)

    $keygen = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($ppbytes, $ppsalt, $KeyDerivationIterations)
    $masterkey = $keygen.GetBytes(32)

    $pwdb = @{
        MasterKey = $ppbytes
        MasterSalt = $ppsalt
        DerivedMasterKey = $masterkey
        Entries = @($passwordEntry)
        EncryptedEntries = $null
    }
<#

how we doin dis? we doin dis this way:

gen random crypto key - do we gain anything from passing this through the KDF? if so then do it otherwise use it raw

this is the master crypto key for the db - regenerated and used to re-encrypt everytyhing after every modification?? could this leak crypto info?

for a new entry - generate a random key just for that row of data, for that password, and encrypt the password using it.
  use the result of KDF(master key, password GUID, 100000) as the encryption key for that row and encrypt the password using it.

with the (sequence, id, name, E(newly generated password)) tuple, add it to the document array, adjusting sequence number as needed

TODO: full json doc encryption and signature

#>

    #$masterkey | Format-Hex
    # TODO: Encryption...
    # $keygen = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($ppbytes, 64, 10000)
    # $key = $keygen.GetBytes(32)
    #$Cipher = [AesGcm]::new()
    $Cipher = [AesCng]::new()

} else {
    $ciphertextjson = Get-Content $DatabaseFile
    # TODO: Decryption...
    $pwdb = $ciphertextjson | ConvertFrom-Json
    $passwordEntry.sequence = $pwdb.Length
}
