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

Requirements: powershell script that works with a default install of windows 10
with powershell 5.1 only and no options of installing newer .net core or
powershell or windows terminal. We are stuck with .net FRAMEWORK 4.8.

==============================================================================
Scripts by OperativeThunny - Galois Counter Mode (GCM) for AES in PowerShell
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
            $new_number_of_bits = $s % 8
            $mask = 0xFF
            # we get the number of bits that we need to preserve in the, probably, last byte, which will be the right most bits:
            $mask = $mask -shr (8-$new_number_of_bits)
            #write-host -f red "This is the mask for the final byte of $($s) bits: 0b$([convert]::tostring($mask, 2).PadLeft(8,'0')) or 0x$([convert]::tostring($mask, 16).PadLeft(2,'0'))"

            if ($s -lt 8) { # it is < instead of <= here because we already handled the case where it is a multiple of 8
                return [byte[]]@($X[0] -band $mask)
            }

            $index_of_final_byte = [Math]::Floor($s/8)

            # TODO: do the rest of this function without allocating multiple new arrays?
            $bytes = $X[0..($index_of_final_byte-1)]

            $final_byte = [byte]($X[$index_of_final_byte])
            #Write-host -f red "The last byte is 0b$([convert]::tostring($final_byte,2).padleft(8,'0')) or 0x$([convert]::tostring($final_byte,16).padleft(2,'0'))"
            $final_byte = [byte]($final_byte -band $mask)
            #Write-host -f red "The last byte after masking is 0b$([convert]::tostring($final_byte,2).padleft(8,'0')) or 0x$([convert]::tostring($final_byte,16).padleft(2,'0'))"
            $final_byte_array = [byte[]]@($final_byte)
            #$final_byte_array = [byte[]]@( [byte] ($X[-1] -band $mask))

            $bytes = ( ([byte[]]$bytes[0..($bytes.length)]) + $final_byte_array )

            return $bytes
        }
    }

    # MSB_s(X) return the s most significant (i.e., left-most) bits, respectively, of X.
    # PRECONDITION: X is a bit string represented in little endian format as a byte array.
    # EXAMPLE: MSB_4 (111011010) = 1110
    # WARNING: NOTE: NOTICE:!!!! THIS IS ASSUMING THE NIST SPECIAL PUBLICATION
    # 800-38D ON PAGE 11 IMPLIES THE MOST SIGNIFICANT BITS RETURNED FROM MSB_s ARE
    # TO BE INTERPRETED AS THE LEFT MOST BITS IN A 8 BIT BYTE SO 1110 IS TREATED AS
    # 0b11100000 INSTEAD OF 0b00001110! THIS IS NOT MADE CLEAR IN THE SPECIAL
    # PUBLICATION!
    static [byte[]]MSB_s([System.UInt64]$s, [byte[]]$X) {
        #Write-Host -f red "S bits: $($s); X length: $($X.Length)"
        if ($s % 8 -eq 0) {
            #Write-Host -f red "start: $(($X.Length-1)) end: $(($X.Length-($s/8)))"
            $bytes = $X[($X.Length-1)..($X.Length-($s/8))]
            #write-host -f red "$($bytes -join ",")"
            [array]::Reverse($bytes)
            return $bytes
        }
        # At this point we know that $s is not a multiple of 8, so we need to
        # find out if s is bigger than 8 and get those bytes up to the non even
        # multiple of 8 then get the last byte and mask it.

        # get the left most number of bits we need to preserve by shifting a
        # byte of all 1s over to the left and filling in the lower bits with 0s
        [byte]$mask = ([byte]0xFF) -shl (8-($s % 8))

        #Write-host -f red "The mask of the final byte: 0b$([convert]::tostring($mask, 2).PadLeft(8,'0'))"

        # we need to get the index of the "final" byte, which in this case,
        # because we are getting the most significant bytes, will be the index
        # in the array in the direction of the zero index, which is the least
        # significant byte, so that index will be the array length minus one
        # (the actual last index) minus the number of most significant bits we
        # need to get converted to whole bytes, so divide by 8. We can factor
        # out the calculation of getting the real last index out of the math to
        # the end to make it look more pretty. We can wrap the whole thing in
        # parentheses because more parentheticals equals more better.
        $index_of_final_byte = (($X.Length - [Math]::Floor($s/8)) - 1)

        #Write-Host -f red "Index of final byte in MSB_$($s): $($index_of_final_byte)"

        if ($s -lt 8) { # it is < instead of <= here because we already handled the case where it is a multiple of 8
            return [byte[]]@( $X[($X.Length-1)] -band $mask )
        }

        # return all the bytes with all the shizz and stuff:
        $return_value = [byte[]]@( $X[($X.Length-1)..($index_of_final_byte)] )
        $return_value[-1] = [byte]($return_value[-1] -band $mask)
        [array]::Reverse($return_value)

        return $return_value
    }
    # 6.2 Incrementing Function
    # For a positive integer s and a bit string X such that len(X)≥s, let the s-bit incrementing function,
    # denoted inc_s(X), be defined as follows:
    # inc_s(X)=MSB_{len(X)-s}(X) || [int(LSB_s(X))+1 mod 2^s]_s
    # In other words, the function increments the right-most s bits of the string, regarded as the binary
    # representation of an integer, modulo 2^s; the remaining, left-most len(X)-s bits remain unchanged.
    static [byte[]]inc_s($s, $X) {
        $MSB = [GCM]::MSB_s((($X.Length*8)-$s), $X)
        $LSB = [GCM]::LSB_s($s, $X)

        if($LSB.Length -le 8) {
            [UInt64]$LSBi = ([UInt64]([BitConverter]::ToUInt64($LSB, 0)))
            $LSBi++
            $LSB = [BitConverter]::GetBytes($LSBi)
        } else {
            # TODO: Convert the LSB to a bit array and increment it.
        }
        return $null
    }

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


########################################################
# TESTS
<#
Test vector:          10101011, 11001101, 11101111, 00010010, 00110100, 01010110, 01111000, 10011010, 10111100, 11011110, 11110000, 00010010, 00110100, 01010110, 01111000, 10011010
Test vector:          ab, cd, ef, 12, 34, 56, 78, 9a, bc, de, f0, 12, 34, 56, 78, 9a
Test vector reversed: 9a, 78, 56, 34, 12, f0, de, bc, 9a, 78, 56, 34, 12, ef, cd, ab
Test vector reversed: 10011010, 01111000, 01010110, 00110100, 00010010, 11110000, 11011110, 10111100, 10011010, 01111000, 01010110, 00110100, 00010010, 11101111, 11001101, 10101011
#>
#                       0b10101011 0b11001101 0b11101111 0b00010010 0b00110100
$test_vector = [byte[]]@(0xAB,      0xCD,      0xEF,      0x12,      0x34,      0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34, 0x56, 0x78, 0x9A)
Write-Output "Test vector: $(($test_vector | ForEach-Object{ ([Convert]::ToString($_, 2)).PadLeft(8, '0') }) -join ", ")"
Write-Output "Test vector: $(($test_vector | ForEach-Object{ ([Convert]::ToString($_, 16)).PadLeft(2, '0') }) -join ", ")"
Write-Output "Test vector reversed: $( ($test_vector | ForEach-Object{ ([Convert]::ToString($_, 16)) })[($test_vector.Length-1)..0] -join ", ")"
Write-Output "Test vector reversed: $( ($test_vector | ForEach-Object{ ([Convert]::ToString($_, 2).PadLeft(8, '0')) })[($test_vector.Length-1)..0] -join ", ")"
# Assertion module from http://cleancode.sourceforge.net/
Import-Module "./CleanCode/Assertion/Assertion.psm1"
if (!(Get-Alias -Name assert -ErrorAction SilentlyContinue)) { New-Alias -Name "assert" -Value "Assert-Expression" }

# [BitConverter]::SingleToUint32Bits(0xAB)
# [BitConverter]::SingleToUint32Bits(0x000000AB)
# [BitConverter]::ToString(0xAB)
# [Convert]::ToString(0xAB, 2)
# $result = [GCM]::LSB_s(6, $(,0xAB))
# [Convert]::ToString($result[0], 2).PadLeft(8, '0') # should be 00101011
assert ( [Convert]::ToString( ([GCM]::LSB_s(6, $(,0xAB)))[0], 2).PadLeft(8, '0') ) "00101011" "Least significant 6 bits of 0xAB should be 101011"

# $result = [GCM]::LSB_s(8, $test_vector)
# [Convert]::ToString($result[0], 16) # should be 0xAB
assert ( [GCM]::LSB_s(8, $test_vector)[0] ) 171 "Least significant 8 bits of ( little endian ) 0xAB, 0xCD, ..., 0x9A should be 0xAB"

# $result = [GCM]::LSB_s(16, $test_vector) # should be 0xAB, 0xCD
# [Convert]::ToString($result[0], 16) + [Convert]::ToString($result[1], 16)
#assert ( $($res = [GCM]::LSB_s(16, $test_vector); (($res[1] -shl 8) -bor ($res[0])) ) )  52651 "Least significant 16 bits of ( little endian ) 0xAB, 0xCD, ..., 0x9A should be 0xCDAB"

# so... this is a bit complicated but you have to think in binary and in types
# here, and also in little endian. Because it requires this thinking I figured a
# paragraph of an explanation is needed for this one line test.
# we are getting a byte array and we need to make sure the bits are right so the
# first element in little endian will go at the end of our value we are building
# up, so the rightmost bits, and we need to OR them together so the second byte
# will be on the left side and if we shift left that 8 bits to make room to OR
# it with the rightmost bits, since it is a byte it will result in a value of 0,
# so we have to first cast the second byte to a 16 bit value and then shift it
# left 8 bits, then or it with the first byte
assert ( $( ([Uint16]($res = [GCM]::LSB_s(16, $test_vector))[1]) -shl 8 -bor $res[0] ) ) 52651 "Least significant 16 bits of ( little endian ) 0xAB, 0xCD, ..., 0x9A should be 0xCDAB"
assert ( $( ([Uint16]($res = [GCM]::LSB_s(16, $test_vector))[1]) -shl 8 -bor $res[0] ) ) 0xCDAB "Least significant 16 bits of ( little endian ) 0xAB, 0xCD, ..., 0x9A should be 0xCDAB"

# ($result = [GCM]::LSB_s(15, $test_vector)) # should be 0b10101011, 0b01001101 or 1001101 without the 0b prefix and all 8 bits
# ($result | ForEach-Object{ [Convert]::ToString($_, 16) }) -join ", "
# [Convert]::ToString($result[0], 16) + [Convert]::ToString($result[1], 2)

#[convert]::tostring(  ((([byte]0xCD) -shl 1) -shr 1), 2).padleft(8, '0')
[byte[]]$result = [GCM]::LSB_s(15, $test_vector)
[Uint16]$left_byte = ([Uint16]($result[1])) -shl 8
Write-Output "This is the most significant byte that is expected to be modified from the original test vector: 0b$([convert]::tostring($left_byte, 2).padLeft(8, '0')) 0x$([convert]::tostring($left_byte, 16).padLeft(4, '0'))"
[Uint16]$right_byte = $result[0]
$last_two_bytes = $left_byte -bor $right_byte
assert ([convert]::tostring($last_two_bytes, 2).padleft(16, '0')) "0100110110101011" "this is the last 15 bits of the test vector (2 bytes). so it needs to be the 15 bits of 0xCDAB (0x7fff & 0xcdab) so 0x4dab or 0b0100110110101011"
#[convert]::tostring(  ((([byte]0xCD) -shl 1) -shr 1), 2).padleft(8, '0')
assert (  [convert]::tostring( ( ((([Uint16] ([byte[]]$res = [GCM]::LSB_s(15, $test_vector))[1]) ) -shl 8) -bor [Uint16]$res[0] ), 2 ).padleft(16, '0')  ) "0100110110101011" "the binary value represented by 0xAB, 0xCD (le) aka 0xCDAB is 1100110110101011. So, the fifteen (15) least significant bits (the right most) ov that would be dropping that left most 1, so it would be 0b0100110110101011"
assert ($last_two_bytes) 0b0100110110101011 "the binary value represented by 0xAB, 0xCD (le) aka 0xCDAB is 1100110110101011. So, the fifteen (15) least significant bits (the right most) ov that would be dropping that left most 1, so it would be 0b0100110110101011"
assert ($last_two_bytes) 0x4dAB "should be 4 dabzzzzzz :)"
assert ($last_two_bytes) 19883 "party like its 19883 y'all"

$result_array = [GCM]::LSB_s(20, $test_vector)
assert (([Uint32]$result_array[2] -shl 16) -bor ([Uint32]$result_array[1] -shl 8) -bor ([uint32]$result_array[0])) 0x000fcdab "The last 2.5 bytes should be 0x00efcdab & 0x000FFFFF = 0x000fcdab"
assert (([Uint32]$result_array[2] -shl 16) -bor ([Uint32]$result_array[1] -shl 8) -bor ([uint32]$result_array[0])) 1035691 "The last 2.5 bytes should be 0x00efcdab & 0x000FFFFF = 0x000fcdab"
assert ( [GCM]::LSB_s(20, $test_vector) ) @(0xab, 0xcd, 0x0f) "20 bits should be 0xab 0xcd 0x0f"

$result_array = [GCM]::LSB_s(23, $test_vector)
assert (([Uint32]$result_array[2] -shl 16) -bor ([Uint32]$result_array[1] -shl 8) -bor ([uint32]$result_array[0])) 0x6fcdab "The last 23 bits should be 0x00efcdab & 0x007FFFFF = 0x6fcdab"
assert (([Uint32]$result_array[2] -shl 16) -bor ([Uint32]$result_array[1] -shl 8) -bor ([uint32]$result_array[0])) 7327147 "The last 23 bits should be 0x00efcdab & 0x007FFFFF = 0x6fcdab"
assert ( [GCM]::LSB_s(23, $test_vector) ) @(0xab, 0xcd, 0x6f) "23 bits should be 0xab 0xcd 0x6f"

$result_array = [GCM]::LSB_s(24, $test_vector)
assert (([Uint32]$result_array[2] -shl 16) -bor ([Uint32]$result_array[1] -shl 8) -bor ([uint32]$result_array[0])) 0xefcdab "The last 24 bits should be 0x00efcdab & 0x00FFFFFF = 0xefcdab"
assert ( [GCM]::LSB_s(24, $test_vector) ) @(0xab, 0xcd, 0xef) "24 bits should be 0xab 0xcd 0xef"
assert ([GCM]::LSB_s(3, [byte[]]@([byte]218, [byte]1))) ([byte[]]@([byte]2)) "test case from the spec"


# MSB TESTS:
assert ([GCM]::MSB_s($test_vector.Length*8, $test_vector)) ($test_Vector) "Most sig bits of 0xAB, 0xCD, ..., 0x9A should be 0x9A, 0x78, ..., 0xAB"
# assert ($test_vector) $false "whatever'"
# assert ($test_vector[0..$(($test_vector.Length)-2)]) $false "whateve2"
assert ([GCM]::MSB_s((($test_vector.Length*8)-8), $test_vector)) ($test_vector[1..$(($test_vector.Length)-1)]) "MSB_{15*8} of TV should be TV without the first element aka index 0. 0x9A, 0x78, ..., 0xCD"



<#
big endian
0x9A,     0x78,     0x56
10011010, 01111000, 01010110

20 bits should be   01010110
10011010, 01111000, 01010000
0x50
22 bits should be
10011010, 01111000, 01010100
0x54

23 bits should be
10011010, 01111000, 01010110
0x56

24 bits should be the same.

lil' endian
0x56, 0x78, 0x9A
01010110, 01111000, 10011010
#>
assert ([GCM]::MSB_s(20, $test_vector)) ([byte[]]@([byte]0x50, [byte]0x78, [byte]0x9a)) "MSB_20 non multiple of 8 most significant bits, lets say 20 bits"
assert ([GCM]::MSB_s(22, $test_vector)) ([byte[]]@([byte]0x54, [byte]0x78, [byte]0x9a)) "MSB_22 non multiple of 8 most significant bits, lets say 22 bits"
assert ([GCM]::MSB_s(23, $test_vector)) ([byte[]]@([byte]0x56, [byte]0x78, [byte]0x9a)) "MSB_23 non multiple of 8 most significant bits, lets say 23 bits"
assert ([GCM]::MSB_s(24, $test_vector)) ([byte[]]@([byte]0x56, [byte]0x78, [byte]0x9a)) "MSB_24"

#                                                                   1110 0000
# WARNING: NOTE: NOTICE:!!!! THIS IS ASSUMING THE NIST SPECIAL PUBLICATION
# 800-38D ON PAGE 11 IMPLIES THE MOST SIGNIFICANT BITS RETURNED FROM MSB_s ARE
# TO BE INTERPRETED AS THE LEFT MOST BITS IN A 8 BIT BYTE SO 1110 IS TREATED AS
# 0b11100000 INSTEAD OF 0b00001110! THIS IS NOT MADE CLEAR IN THE SPECIAL
# PUBLICATION!
assert ([GCM]::MSB_s(4, [byte[]]@([byte]0b00000000, [byte]0b0000000011101101))) ([byte[]]@([byte]0b0000000011100000)) "# MSB_4 (1110 1101 0) = 1110. - MSB_4 0b111011010 should be 0b1100"
assert ([GCM]::MSB_s(4, [byte[]]@([byte]0, [byte]237))) ([byte[]]@([byte]224)) "# MSB_4 (1110 1101 0) = 1110. - MSB_4 1110 1101 0 should be 0b1100"
assert ([GCM]::MSB_s(4, [byte[]]@([byte]0b010, [byte]0b01110110))) ([byte[]]@([byte]0b01110000)) "MSB_4(01110110 10) = 0111"
assert ([GCM]::MSB_s(4, [byte[]]@([byte]2, [byte]118))) ([byte[]]@([byte]112)) "MSB_4 0b111011010 should be 0b1100"
