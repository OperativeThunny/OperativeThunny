#!/usr/bin/env pwsh
<#
file: pass.ps1

random password generator and local "password database" manager.

Requirements:
    powershell script that works with a default install of windows 10 with
      powershell 5.1 only and no options of installing newer .net core or
      powershell or windows terminal. We are stuck with .net FRAMEWORK 4.8.
    Uses hardware x.509 PKI smartcards to encrypt master key and sign encrypted DB.

    This is a proof of concept and is not intended to be used in production.

Proposed method of operation:
   would I gain any security if I took a cryptographically secure random
   generated sequence of bytes intended to be used as an AES crypto key and pass
   it through a KDF with a salt?

   I planned on every time a change is made to regenerate themaster key and
   re-encrypt everything with the new key, which is another question I had:
   would continualy re-encrypting with new keys leak information?

   The setup I'm thinking of implementing is like this: Securely gen 32 bytes
   for the master key then securely generate some amount of bytes for a salt and
   feed the master key and salt into the KDF to get a generator for further
   keys, use 32 bytes from that as the master encryption key, K, fed into AES
   for encrypting the json document, then for each password you generate or add
   to the password document you generate a guid to act as an ID. Each record
   would be (sequence num, uuid, name, password) and then using 32 bytes from
   the master key gen as the "password" and salted with the UUID for the
   particular password fed into a new KDF instance, you encrpt each individual
   password, then once all the passwords are encrypted using their unique
   derived keys you encrypt the whole array of entry rows using the master
   encryption key, K, then you encrypt the original salt and master key using
   the users's certificate, and sign the whole document of encrypted key and
   encrypted row data using the certificate. Then when youneed to search based
   on name, you can decrypt thejson array and rehydrate it into an array of
   objects and search through the name fields, and when you find the right
   password you can regen the individualized necryption key for that password
   and decrypt and return the password

   question: anythign gained with all the usages of KDF? And if I regenerate and
   re-encrypt the whole document and each row every time a change is made using
   this method, doe3s that leak information?

==============================================================================
Scripts by OperativeThunny - Command line password manager using AES-256-GCM and
x.509 PKI smartcards
Copyright (C) 2023 @OperativeThunny

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
==============================================================================

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

[char[]]$AllCharacterClasses = @() `
  + $AsciiCharacterClasses.lowspecials `
  + $AsciiCharacterClasses.numerals `
  + $AsciiCharacterClasses.lowmidspecials `
  + $AsciiCharacterClasses.upperalpha `
  + $AsciiCharacterClasses.highmidspecials `
  + $AsciiCharacterClasses.loweralpha `
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
        # # I really dont know if this is any better than straight mod but according to this, straight mod is not cryptographically secure even used with a cryptographically secure input: https://crypto.stackexchange.com/questions/7996/correct-way-to-map-random-number-to-defined-range
        # $randomIndex = Get-Random -SetSeed $curRnd -Minimum 0 -Maximum $alphabetLen
        # $randomPasswordIndicies[$i] = $randomIndex
        # $randomPasswordChars[$i] = $AllCharacterClasses[$randomIndex]
        # Maybe this will be better, to keep regenerating a random buffer until a byte at our current index is less than the array bounds:
        $regenIterations = 0
        $regenChecks = 0
        do {
            $currentLength = $randomPasswordSeedRegen.Length
            $rng.GetBytes($randomPasswordSeedRegen, 0, $currentLength)
            for ([int] $j = 0; $j -lt $currentLength -and $curRnd -ge $alphabetLen; $j++) {
                $curRnd = $randomPasswordSeedRegen[$j]
                $regenChecks++
            }
            $regenIterations++
        } while ($curRnd -ge $alphabetLen) # What is the probability this loop is non-terminating, forever?

        Write-Debug "We had to regenerate random bytes $($regenIterations) times for index $($i), checking each regenerated byte $($regenChecks) times."
        $totalRegens += $regenIterations + $regenChecks
    }
    $randomPasswordIndicies[$i] = $curRnd # We probably dont need this but its neat to have.
    $randomPasswordChars[$i] = $AllCharacterClasses[$curRnd]
}
Write-Debug "We had to regenerate random bytes $($totalRegens) times for this password!"
$randomPassword = [string]::new($randomPasswordChars)

if ($Operation -eq "generate") {
    # generate simply generates a new random string and does nothing else. "new" does the same thing but also adds it to the database.
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
    [byte[]]$password
    [byte[]]$secure_note

    PasswordEntry([string]$sequence, [string]$id, [string]$name, [byte[]]$password, [byte[]]$secure_note) {
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

$passwordEntry = [PasswordEntry]::new(0, $null, $pwname, [System.Text.Encoding]::UTF8.GetBytes($randomPassword), [System.Text.Encoding]::UTF8.GetBytes($NewEntryDescription))

function E([byte[]]$k, [byte[]]$v) {
    #https://gist.github.com/loadenmb/8254cee0f0287b896a05dcdc8a30042f
    #[byte[]].
    # $k | Add-Member -MemberType ScriptMethod -Name "op_ExclusiveOr" -Value {
    #     param($v) # WTB tutorial ob powershell operator overloading
    #     [System.Collections.Generic.List[byte]]$ret = [System.Collections.Generic.List[byte]]::new()
    #     for($i = 0; $i -lt $v.Length; $i++) {
    #         $ret.add($this[$i % $this.Length] -bxor $v[$i])
    #     }
    #     return $ret.ToArray()
    # }
    # return $k -bxor $v # lol this is bad its just temporary trust me :D

    for($i = 0; $i -lt $v.Length; $i++) {
        $v[$i] = $k[$i % $k.Length] -bxor $v[$i]
    }
    return $v
}

#E [byte[]]([char[]]"test") [byte[]]([char[]]"test")

[System.Text.Encoding]::UTF8.GetBytes($randomPassword) | E $masterkey

if(!(Test-Path $DatabaseFile)) {
    [byte[]]$ppbytes = [byte[]]::new(32) # pp=passphrase :)
    [byte[]]$ppsalt = [System.Byte[]]::new(32)
    $rng.GetBytes($ppsalt, 0, $ppsalt.Length)
    $rng.GetBytes($ppbytes, 0, $ppbytes.Length)

    $keygen = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($ppbytes, $ppsalt, $KeyDerivationIterations)
    $masterkey = $keygen.GetBytes(32)

    $pwdb = [PasswordDatabase]::new()
    $pwdb.MasterKey = $ppbytes
    $pwdb.MasterSalt = $ppsalt
    $pwdb.DerivedMasterKey = $masterkey
    $pwdb.Entries = [System.Collections.Generic.Dictionary[string, PasswordEntry]]::new()
    $pwdb.Entries.Add($passwordEntry.id, $passwordEntry)
    $pwdb.EncryptedEntries = $null

    #$Cipher = [AesGcm]::new()
    #$Cipher = [AesCng]::new()
    #$Cipher = [Aes]::Create()
    $Cipher = [AesManaged]::Create()
    $Cipher.BlockSize = 128
    $Cipher.KeySize = 256
    #$Cipher.Mode = [CipherMode]::GCM\ # hmmmmmmmmmm.......... https://gist.github.com/ctigeek/2a56648b923d198a6e60?permalink_comment_id=3794601

    # LOOKS LIKE WE ARE GOING TO IMPLEMENT AES-256-GCM OURSELF BOIS!
    # https://csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf
    # NOTE: THERE IS A VULNERABILITY IF NONCE VALUES ARE RE-USED WITH THE SAME ENCRYPTION KEY! DON'T DO THAT!
    # https://ludvigknutsmark.github.io/posts/breaking_aes_gcm_part2/
    # https://github.com/Metalnem/aes-gcm-siv/blob/master/src/Cryptography/AesGcmSiv.cs
    # https://gist.github.com/Darryl-G/d1039c2407262cb6d735c3e7a730ee86
    # https://www.it-implementor.co.uk/2021/04/powershell-encrypt-decrypt-openssl-aes256-cbc.html
    # https://datatracker.ietf.org/doc/html/rfc8452
    # https://en.wikipedia.org/wiki/AES-GCM-SIV
    # https://stackoverflow.com/questions/10655026/gcm-multiplication-implementation
    # https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf
    #https://github.com/traviscross/bgaes/blob/master/gf128mul.h
} else {
    $ciphertextjson = Get-Content $DatabaseFile
    # TODO: Decryption...
    $pwdb = $ciphertextjson | ConvertFrom-Json
    $passwordEntry.sequence = $pwdb.Length
}
