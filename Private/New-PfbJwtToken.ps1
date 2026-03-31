function New-PfbJwtToken {
    <#
    .SYNOPSIS
        Generates a signed JWT (JSON Web Token) for FlashBlade OAuth2 authentication.
    .DESCRIPTION
        Internal helper that creates a JWT signed with an RSA private key.
        Used by Connect-PfbArray for the certificate-based authentication flow.
        Compatible with PowerShell 5.1 (uses .NET crypto classes directly).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$KeyId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Issuer,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [string]$PrivateKeyFile,
        [Parameter()] [System.Security.SecureString]$PrivateKeyPassword
    )

    # Base64url encoding helper
    function ConvertTo-Base64Url {
        param([byte[]]$Bytes)
        [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }

    # Read the PEM private key file
    if (-not (Test-Path $PrivateKeyFile)) {
        throw "Private key file not found: $PrivateKeyFile"
    }
    $pemContent = Get-Content $PrivateKeyFile -Raw

    # Build JWT header
    $header = @{
        kid = $KeyId
        typ = 'JWT'
        alg = 'RS256'
    } | ConvertTo-Json -Compress

    # Build JWT payload
    $now = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $payload = @{
        aud = $ClientId
        sub = $Username
        iss = $Issuer
        iat = $now
        exp = $now + 300  # 5 minute expiry
    } | ConvertTo-Json -Compress

    $headerB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($header))
    $payloadB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($payload))
    $unsigned = "${headerB64}.${payloadB64}"

    # Parse RSA private key from PEM
    $pemBody = $pemContent -replace '-----BEGIN .*-----', '' -replace '-----END .*-----', '' -replace '\s', ''
    $keyBytes = [Convert]::FromBase64String($pemBody)

    # Detect key format and load
    $rsa = $null
    if ($pemContent -match 'BEGIN RSA PRIVATE KEY') {
        # PKCS#1 format
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $rsa = [System.Security.Cryptography.RSA]::Create()
            $bytesRead = 0
            $rsa.ImportRSAPrivateKey($keyBytes, [ref]$bytesRead)
        }
        else {
            # PS 5.1 — use RSACryptoServiceProvider with manual PKCS#1 parsing
            $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
            # Try importing as PKCS#1 via CNG if available
            try {
                $cng = [System.Security.Cryptography.CngKey]::Import($keyBytes, [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
                $rsa = New-Object System.Security.Cryptography.RSACng($cng)
            }
            catch {
                # Fallback: wrap PKCS#1 in PKCS#8 envelope
                $pkcs8 = ConvertTo-Pkcs8FromPkcs1 -Pkcs1Bytes $keyBytes
                $cng = [System.Security.Cryptography.CngKey]::Import($pkcs8, [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
                $rsa = New-Object System.Security.Cryptography.RSACng($cng)
            }
        }
    }
    elseif ($pemContent -match 'BEGIN PRIVATE KEY') {
        # PKCS#8 format
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $rsa = [System.Security.Cryptography.RSA]::Create()
            $bytesRead = 0
            $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$bytesRead)
        }
        else {
            # PS 5.1 — CNG can import PKCS#8 directly
            $cng = [System.Security.Cryptography.CngKey]::Import($keyBytes, [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
            $rsa = New-Object System.Security.Cryptography.RSACng($cng)
        }
    }
    elseif ($pemContent -match 'BEGIN ENCRYPTED PRIVATE KEY') {
        if (-not $PrivateKeyPassword) {
            throw "Private key is encrypted. Provide -PrivateKeyPassword."
        }
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $rsa = [System.Security.Cryptography.RSA]::Create()
            $bytesRead = 0
            $plainPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrivateKeyPassword)
            )
            $rsa.ImportEncryptedPkcs8PrivateKey([System.Text.Encoding]::UTF8.GetBytes($plainPw), $keyBytes, [ref]$bytesRead)
            $plainPw = $null
        }
        else {
            throw "Encrypted private keys require PowerShell 7+. Please use an unencrypted key or upgrade PowerShell."
        }
    }
    else {
        throw "Unsupported private key format in '$PrivateKeyFile'. Expected PEM-encoded RSA private key (PKCS#1 or PKCS#8)."
    }

    if (-not $rsa) {
        throw "Failed to load RSA private key from '$PrivateKeyFile'."
    }

    # Sign the JWT
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($unsigned)
    $signature = $rsa.SignData($dataBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $signatureB64 = ConvertTo-Base64Url $signature

    return "${unsigned}.${signatureB64}"
}

function ConvertTo-Pkcs8FromPkcs1 {
    <#
    .SYNOPSIS
        Wraps a PKCS#1 RSA private key in a PKCS#8 envelope for CNG import.
    #>
    param([byte[]]$Pkcs1Bytes)

    # PKCS#8 header for RSA (OID 1.2.840.113549.1.1.1)
    $oid = [byte[]]@(0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00)

    # Wrap PKCS#1 key in OCTET STRING
    $octetHeader = New-Object System.Collections.Generic.List[byte]
    $octetHeader.Add(0x04)
    $lenBytes = Get-DerLengthBytes $Pkcs1Bytes.Length
    $octetHeader.AddRange([byte[]]$lenBytes)
    $octetString = $octetHeader.ToArray() + $Pkcs1Bytes

    # Build SEQUENCE { version INTEGER 0, algorithm AlgorithmIdentifier, privateKey OCTET STRING }
    $version = [byte[]]@(0x02, 0x01, 0x00)
    $innerContent = $version + $oid + $octetString

    $seqHeader = New-Object System.Collections.Generic.List[byte]
    $seqHeader.Add(0x30)
    $seqLenBytes = Get-DerLengthBytes $innerContent.Length
    $seqHeader.AddRange([byte[]]$seqLenBytes)

    return $seqHeader.ToArray() + $innerContent
}

function Get-DerLengthBytes {
    param([int]$Length)
    if ($Length -lt 128) {
        return [byte[]]@([byte]$Length)
    }
    elseif ($Length -lt 256) {
        return [byte[]]@(0x81, [byte]$Length)
    }
    elseif ($Length -lt 65536) {
        return [byte[]]@(0x82, [byte]($Length -shr 8), [byte]($Length -band 0xFF))
    }
    else {
        return [byte[]]@(0x83, [byte]($Length -shr 16), [byte](($Length -shr 8) -band 0xFF), [byte]($Length -band 0xFF))
    }
}
