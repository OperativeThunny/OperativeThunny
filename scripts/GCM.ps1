#!/usr/bin/env pwsh
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
   X>>1 The bit string that results from discarding the rightmost bit of the bit string X and prepending a ‘0’ bit on the left.
#>
#>

using namespace System.Security.Cryptography



function [byte[]]LSB_s([System.UInt64]$s, [byte[]]$X) {
    # TODO: special case for s not divisible by 8 but s is less than 8
    if ($s % 8 -eq 0) {
        return $X[0..(($s/8)-1)]
    } else {
        $bytes = $X[0..(([Math]::Floor($s/8))-1)]
        $s = $s % 8
        $mask = 0xFF
        $mask = $mask -shr (8-$s)
        $bytes = ([byte[]]$bytes[0..($bytes.length)] + [byte[]]@( [byte] ($X[-1] -band $mask)))
        return $bytes
    }
}

# [BitConverter]::SingleToUint32Bits(0xAB)
# [BitConverter]::SingleToUint32Bits(0x000000AB)
# [BitConverter]::ToString(0xAB)
[Convert]::tostring(0xAB, 2)
[GCM]::LSB_s(5, $(,0xAB))


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
        # TODO: special case for s divisble by 8
        if ($s % 8 -eq 0) {
            return $X[0..(($s/8)-1)]
        } else {
            $bytes = $X[0..(([Math]::Floor($s/8))-1)]
            $s = $s % 8
            # $mask = 0x01
            # # TODO: instead of building up from zeros, maybe start with all ones and shift right?
            # for ($i = 0; $i -lt $s-1; $i++) {
            #     $mask = $mask -bor ($mask -shl 1)
            # }
            $mask = 0xFF
            $mask = $mask -shr (8-$s)
            #$bytes = [byte[]]@([byte[]]$bytes[0..($bytes.Length-1)],($X[-1] -band $mask))
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



