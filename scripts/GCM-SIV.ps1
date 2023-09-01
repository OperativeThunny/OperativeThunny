#!/usr/bin/env pwsh
<#

==============================================================================
Scripts by OperativeThunny
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

using module "./GCM.ps1"

class GCM_SIV : GCM {
    hidden [void] Init() {}
    GCM_SIV() {
        $this.Init()
    }
}



