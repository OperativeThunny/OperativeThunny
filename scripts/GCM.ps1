#!/usr/bin/env pwsh
<#

Implementation of the Galois Counter Mode (GCM) for AES in PowerShell.

In general it is a block cipher mode of operation that uses a Galois Field
multiplication to generate a Message Authentication Code (MAC) for the purposes
of AEAD (Authenticated Encryption with Associated Data).

This exists because the .NET Framework that comes by default with Windows 10
does not have a built-in implementation of GCM for AES. I am writing this
because I want to use GCM with AES in PowerShell and I don't want to have to
(and do not have admin ability to) install .NET Core or .NET 5+ on my Windows 10
machine.

Requirements:
    powershell script that works with a default install of windows 10 with
      powershell 5.1 only and no options of installing newer .net core or
      powershell or windows terminal. We are stuck with .net FRAMEWORK 4.8.

Do not use the same nonce or IV with the same key more than once. This can lead
to the same keystream being generated, which in turn leads to the same
ciphertext being produced. If an attacker detects this, they can recover the
plaintext from the ciphertext by XORing the two ciphertexts together. NOTE:
THERE IS A VULNERABILITY IF NONCE/IV VALUES ARE RE-USED WITH THE SAME ENCRYPTION
KEY! DON'T DO THAT!

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
   X>>1	The bit string that results from discarding the rightmost bit of the bit string X and prepending a ‘0’ bit on the left.
#>

using namespace System.Security.Cryptography

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
#https://stackoverflow.com/questions/38381890/powershell-bytes-to-bit-array
    static [byte[]] BitToByteArray ( [System.Collections.BitArray]$BitArray ) {

        $numBytes = [System.Math]::Ceiling($BitArray.Count / 8)

        $bytes = [byte[]]::new($numBytes)
        $byteIndex = 0
        $bitIndex = 0

        for ($i = 0; $i -lt $BitArray.Count; $i++) {
            if ($BitArray[$i]) {
                $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl (7 - $bitIndex))
            }
            $bitIndex++
            if ($bitIndex -eq 8) {
                $bitIndex = 0
                $byteIndex++
            }
        }

        return $bytes
    }

    # The output of the forward cipher function of the block cipher under the key K applied to the block X.
    # Assumes the key is already set on the block cipher instance.
    #[byte[]]CIPH($K, $X) {
    #[System.Collections.Specialized.BitVector32]
    [byte[]]CIPH_K([byte[]]$X) {
        return $this.block_cipher_instance.EncryptEcb($X, [PaddingMode]::None)
    }

    # Given a bit string X and a non-negative integer s such that len(X)≥s, the functions LSB_s(X) and
    # MSB_s(X) return the s least significant (i.e., right-most) bits and the s most significant (i.e., left-
    # most) bits, respectively, of X. For example, LSB_3 (111011010) = 010, and
    # MSB_4 (111011010) = 1110.
    # big endian means most significant byte is first
    # little endian means least significant byte is first (this is what we are using) https://en.wikipedia.org/wiki/Endianness
    # the PDF document for the specification of GCM says to use  "The convention
    # for interpreting strings as polynomials is “little endian”: i.e., if u is
    # the variable of the polynomial, then the block x0x1...x127 corresponds to
    # the polynomial x0 + x1 u + x2 u2 + ... + x127 u 127."
    # so index 0 of the input array X is the rightmost 8 bits in the bit string.
    static [byte[]]LSB_s([System.UInt64]$s, [byte[]]$X) {
        if ($s % 8 -eq 0) {
            return $X[0..(($s/8)-1)]
        } else {
            $bytes = $X[0..(([Math]::Floor($s/8))-1)]

            $mask = 0xFF
            $mask = $mask -shr (8-$s)

            if ($s -lt 8) {
                return [byte[]]@($X[0] -band $mask)
            }

            $bytes = ([byte[]]$bytes[0..($bytes.length)] + [byte[]]@( [byte] ($X[-1] -band $mask)))
            return $bytes
        }
    }

    [byte[]]MSB_s([System.UInt64]$s, [byte[]]$X) {
        return $null
    }
    # 6.2 Incrementing Function
    # For a positive integer s and a bit string X such that len(X)≥s, let the s-bit incrementing function,
    # denoted inc_s(X), be defined as follows:
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

    (((Programmer's note: the extra xor symbol in the first line of each piecewise function below is there intentionally,
    but is to be discarded as you can tell it is not valid in the context because there is no second operand.
    it is simply there so the if statements line up perfectly in my current font.)))

        Z_{i+1} =
                    ⎧  Z_i⊕          if x_i = 0;
                    ⎨  Z_i ⊕ V_i     if x_i = 1.
                    ⎩

        V_{i+1} =
                    ⎧ V_i >> 1⊕      if LSB_1 (V_i) = 0;
                    ⎨(V_i >> 1)⊕R    if LSB_1 (V_i) = 1.
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

<#



#>

    [byte[]] AE($K, $IV, $P, $A) {
        return $null
    }

    [byte[]] AD($K, $IV, $C, $A) {
        return $null
    }
}

#                       0b10101011 0b11001101 0b11101111 0b00010010 0b00110100
$testVector = [byte[]]@(0xAB,      0xCD,      0xEF,      0x12,      0x34,      0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34, 0x56, 0x78, 0x9A)
. "./CleanCode/"

# [BitConverter]::SingleToUint32Bits(0xAB)
# [BitConverter]::SingleToUint32Bits(0x000000AB)
# [BitConverter]::ToString(0xAB)
[Convert]::ToString(0xAB, 2)
$result = [GCM]::LSB_s(6, $(,0xAB))
[Convert]::ToString($result[0], 2) # should be 101011

$result = [GCM]::LSB_s(8, $testVector)
[Convert]::ToString($result[0], 16) # should be 0xAB

$result = [GCM]::LSB_s(16, $testVector) # should be 0xAB, 0xCD
[Convert]::ToString($result[0], 16) + [Convert]::ToString($result[1], 16)

$result = [GCM]::LSB_s(15, $testVector) # should be 0b10101011, 0b01001101 or 1001101 without the 0b prefix and all 8 bits
($result | %{ [Convert]::ToString($_, 16) }) -join ", " # TODO: TEST FAILURE!!!
[Convert]::ToString($result[0], 16) + [Convert]::ToString($result[1], 2)

$result = [GCM]::LSB_s(23, $testVector)

# TODO: assert
