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
    $Cipher.BlockSize = 256
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

<#
Do not use the same nonce or IV with the same key more than once. This can lead to the same keystream being generated, which in turn leads to the same ciphertext being produced.
If an attacker detects this, they can recover the plaintext from the ciphertext by XORing the two ciphertexts together.
NOTE: THERE IS A VULNERABILITY IF NONCE/IV VALUES ARE RE-USED WITH THE SAME ENCRYPTION KEY! DON'T DO THAT!
It is used by the GCM mode of operation for AES.
In general it is a block cipher mode of operation that uses a Galois Field multiplication to generate a Message Authentication Code (MAC) for the purposes of AEAD (Authenticated Encryption with Associated Data).
.LINK
    https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf
    https://csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf
.LINK
    https://ludvigknutsmark.github.io/posts/breaking_aes_gcm_part2/
    https://github.com/Metalnem/aes-gcm-siv/blob/master/src/Cryptography/AesGcmSiv.cs
    https://gist.github.com/Darryl-G/d1039c2407262cb6d735c3e7a730ee86
    https://www.it-implementor.co.uk/2021/04/powershell-encrypt-decrypt-openssl-aes256-cbc.html
    https://datatracker.ietf.org/doc/html/rfc8452
    https://stackoverflow.com/questions/10655026/gcm-multiplication-implementation
.NOTES
<#
    A	The additional authenticated data
    C	The ciphertext.
    H	The hash subkey.
    ICB	The initial counter block
    IV	The initialization vector.
    K	The block cipher key.
    P	The plaintext.
    R	The constant within the algorithm for the block multiplication operation.
    T	The authentication tag.
    t	The bit length of the authentication tag.
    0^s	The bit string that consists of s ‘0’ bits.
#>
#>
class GCM {
    [System.Security.Cryptography.SymmetricAlgorithm]$block_cipher_instance

    hidden [void] Init([System.Security.Cryptography.SymmetricAlgorithm]$block_cipher_instance) {
        $this.block_cipher_instance = $block_cipher_instance
    }

    GCM() {
        $this.Init($null)
    }

    GCM([System.Security.Cryptography.SymmetricAlgorithm]$block_cipher_instance) {
        $this.Init($block_cipher_instance)
    }

    # The output of the forward cipher function of the block cipher under the key K applied to the block X.
    [byte[]]CIPH($K, $X) {
        $this.block_cipher_instance.Key = $K
        return $this.block_cipher_instance.EncryptEcb($X, [PaddingMode]::None)
    }
    [byte[]]CIPH_K($K, $X) {return CIPH($K,$X)}

    # Given a bit string X and a non-negative integer s such that len(X)≥s, the functions LSB_s(X) and
    # MSB_s(X) return the s least significant (i.e., right-most) bits and the s most significant (i.e., left-
    # most) bits, respectively, of X. For example, LSB_3 (111011010) = 010, and
    # MSB_4 (111011010) = 1110.
    [byte[]]LSB_s($s, $X) {return $null}
    [byte[]]MSB_s($s, $X) {return $null}
    # 6.2 Incrementing Function
    # For a positive integer s and a bit string X such that len(X)≥s, let the s-bit incrementing function,
    # denoted incs(X), be defined as follows:
    # inc_s(X)=MSB_{len(X)-s}(X) || [int(LSB_s(X))+1 mod 2^s]_s
    # In other words, the function increments the right-most s bits of the string, regarded as the binary
    # representation of an integer, modulo 2^s; the remaining, left-most len(X)-s bits remain unchanged.
    [byte[]]inc_s($s, $X) {return $null}

    # 6.3 Multiplication Operation on Blocks
    # Let R be the bit string 11100001 || 0^120 . Given two blocks X and Y, Algorithm 1 below
    # computes a “product” block, denoted X•Y:
    <#
    Algorithm 1: X•Y

    Input:
        blocks X, Y.

    Output:
        block  X• Y.

    Steps:
    1. Let x_0 x_1...x_127 denote the sequence of bits in X.
    2. Let Z_0 = 0^128 and V_0 = Y.
    3. For i = 0 to 127, calculate blocks Zi+1 and Vi+1 as follows:

        Z_{i+1} =
                    ⎧  Z_i          if x_i = 0;
                    ⎨  Z_i ⊕ V_i   if x i = 1.
                    ⎩

        V_{i+1} =
                    ⎧ V_i >> 1           if LSB_1 (V_i) = 0;
                    ⎨(V_i >> 1)⊕R       if LSB_1 (V_i) = 1.
                    ⎩

    4. Return Z_128

    The • operation on (pairs of) the 2^128 possible blocks corresponds to the multiplication operation
    for the binary Galois (finite) field of 2^128 elements. The fixed block, R, determines a
    representation of this field as the modular multiplication of binary polynomials of degree less
    than 128. The convention for interpreting strings as polynomials is “little endian”: i.e., if u is
    the variable of the polynomial, then the block x_0 x_1...x_127 corresponds to the polynomial x_0 + x_1 u +
    x_2 u^2 + ... + x_127 u^127. The XOR operation is used to add coefficients of “like” terms during the
    multiplication. The reduction modulus is the polynomial of degree 128 that corresponds to R || 1.
    Ref. [6] discusses this field in detail.
    For a positive integer i, the ith power of a block X with this multiplication operation is denoted
    X^i. For example, H^2 =H•H, H^3 =H•H•H, etc.
    #>
    <#
    .SYNOPSIS
        This is a function that multiplies two 128-bit Galois Field elements.
    .DESCRIPTION
        The product of two blocks, X and Y, regarded as elements of a certain binary Galois field.
        X \cdot Y
    .INPUTS
        Two 128-bit Galois Field elements.
    .OUTPUTS
        The product of the two 128-bit Galois Field elements.
    #>
    [byte[]] GF128Mul([byte[]]$X, [byte[]]$Y) {
        return $null
    }

    # The output of the GHASH function under the hash subkey H applied to the bit string X.
    [byte[]]GHASH($H, $X) {return $null}

    # The output of the GCTR function for a given block cipher with key K applied to the bit string X with an initial counter block ICB.
    [byte[]]GCTR($K, $ICB, $X) {return $null}



    [byte[]] AE($K, $IV, $P, $A) {
        return $null
    }

    [byte[]] AD($K, $IV, $C, $A) {
        return $null
    }
}

<#
.LINK
    https://en.wikipedia.org/wiki/AES-GCM-SIV
    https://datatracker.ietf.org/doc/html/rfc8452
.NOTES
3.  POLYVAL

   The GCM-SIV construction is similar to GCM: the block cipher is used
   in counter mode to encrypt the plaintext, and a polynomial
   authenticator is used to provide integrity.  The authenticator in
   GCM-SIV is called POLYVAL.

   POLYVAL, like GHASH (the authenticator in AES-GCM; see [GCM],
   Section 6.4), operates in a binary field of size 2^128.  The field is
   defined by the irreducible polynomial x^128 + x^127 + x^126 + x^121 +
   1.  The sum of any two elements in the field is the result of XORing
   them.  The product of any two elements is calculated using standard
   (binary) polynomial multiplication followed by reduction modulo the
   irreducible polynomial.

   We define another binary operation on elements of the field:
   dot(a, b), where dot(a, b) = a * b * x^-128.  The value of the field
   element x^-128 is equal to x^127 + x^124 + x^121 + x^114 + 1.  The
   result of this multiplication, dot(a, b), is another field element.

   Polynomials in this field are converted to and from 128-bit strings
   by taking the least significant bit of the first byte to be the
   coefficient of x^0, the most significant bit of the first byte to be
   the coefficient of x^7, and so on, until the most significant bit of
   the last byte is the coefficient of x^127.

   POLYVAL takes a field element, H, and a series of field elements
   X_1, ..., X_s.  Its result is S_s, where S is defined by the
   iteration S_0 = 0; S_j = dot(S_{j-1} + X_j, H), for j = 1..s.

   We note that POLYVAL(H, X_1, X_2, ...) is equal to
   ByteReverse(GHASH(ByteReverse(H) * x, ByteReverse(X_1),
   ByteReverse(X_2), ...)), where ByteReverse is a function that
   reverses the order of 16 bytes.  See Appendix A for a more detailed
   explanation.
#>
class GCM_SIV : GCM {
    hidden [void] Init() {}
    GCM_SIV() {
        $this.Init()
    }
}



