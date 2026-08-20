#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'New-PfbJwtToken' {
    Context 'BEGIN ENCRYPTED PRIVATE KEY (PrivateKeyPassword decryption)' {
        BeforeAll {
            # RSA.ExportEncryptedPkcs8PrivateKeyPem/PbeParameters are .NET Core 3.0+/.NET 5+
            # only -- they don't exist on .NET Framework 4.x (Windows PowerShell 5.1), so this
            # fixture can only be generated there. The tests below that consume it are skipped
            # on 5.1 (see -Skip: guards); a separate 5.1-only test further down covers the
            # PowerShell 7+ requirement error instead.
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                # Generate a real encrypted PKCS#8 key at runtime -- never committed to source control.
                # Same technique used in Tests/Connect-PfbArray.OAuth2TokenRefresh.Tests.ps1.
                $script:plainPassword = 'super-secret-jwt-test-password'
                $script:rsa = [System.Security.Cryptography.RSA]::Create(2048)
                $pbeParams = [System.Security.Cryptography.PbeParameters]::new(
                    [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                    100000)
                $keyPem = $script:rsa.ExportEncryptedPkcs8PrivateKeyPem($script:plainPassword, $pbeParams)
                $script:keyPath = Join-Path $TestDrive 'encrypted-jwt-test-key.pem'
                Set-Content -Path $script:keyPath -Value $keyPem -NoNewline
            }
        }

        It 'mints a validly-signed JWT by decrypting the encrypted PKCS#8 private key' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
            # Regression coverage for the fix that wraps the SecureStringToBSTR/PtrToStringAuto/
            # ImportEncryptedPkcs8PrivateKey sequence in try/finally with ZeroFreeBSTR. Actually
            # inspecting whether the unmanaged BSTR was zeroed/freed isn't practically assertable
            # from black-box Pester -- a broken ZeroFreeBSTR usage (wrong pointer, double free)
            # would instead throw or corrupt the RSA import, which this functional assertion
            # would catch. So this test proves the function still mints a correct JWT end-to-end.
            $securePassword = ConvertTo-SecureString $script:plainPassword -AsPlainText -Force
            $keyPathParam = $script:keyPath

            $jwt = InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                keyPathParam    = $keyPathParam
                securePassword  = $securePassword
            } {
                New-PfbJwtToken -KeyId 'key-1' -ClientId 'client-1' -Issuer 'myapp' `
                    -Username 'pureuser' -PrivateKeyFile $keyPathParam -PrivateKeyPassword $securePassword
            }

            $jwt | Should -Not -BeNullOrEmpty
            $parts = $jwt -split '\.'
            $parts.Count | Should -Be 3

            # Decode header and payload to confirm the claims round-tripped correctly.
            function ConvertFrom-Base64Url {
                param([string]$Text)
                $padded = $Text.Replace('-', '+').Replace('_', '/')
                switch ($padded.Length % 4) {
                    2 { $padded += '==' }
                    3 { $padded += '=' }
                }
                [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
            }

            $header  = ConvertFrom-Base64Url $parts[0] | ConvertFrom-Json
            $payload = ConvertFrom-Base64Url $parts[1] | ConvertFrom-Json

            $header.alg  | Should -Be 'RS256'
            $header.kid  | Should -Be 'key-1'
            $payload.aud | Should -Be 'client-1'
            $payload.iss | Should -Be 'myapp'
            $payload.sub | Should -Be 'pureuser'

            # Verify the signature is actually valid for the unsigned header.payload against the
            # public key -- proves the correct private key was successfully decrypted and used.
            $unsigned = "$($parts[0]).$($parts[1])"
            $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($unsigned)
            # Base64url-decode the signature to raw bytes directly (not via the UTF8 text helper
            # above, which would corrupt binary signature data).
            $padded = $parts[2].Replace('-', '+').Replace('_', '/')
            switch ($padded.Length % 4) {
                2 { $padded += '==' }
                3 { $padded += '=' }
            }
            $signatureBytes = [Convert]::FromBase64String($padded)

            $isValid = $script:rsa.VerifyData($dataBytes, $signatureBytes, `
                [System.Security.Cryptography.HashAlgorithmName]::SHA256, `
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $isValid | Should -BeTrue
        }

        It 'throws when the encrypted key is provided without a PrivateKeyPassword' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
            $keyPathParam = $script:keyPath

            {
                InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                    keyPathParam = $keyPathParam
                } {
                    New-PfbJwtToken -KeyId 'key-1' -ClientId 'client-1' -Issuer 'myapp' `
                        -Username 'pureuser' -PrivateKeyFile $keyPathParam
                }
            } | Should -Throw -ExpectedMessage '*Provide -PrivateKeyPassword*'
        }
    }

    Context 'BEGIN ENCRYPTED PRIVATE KEY on Windows PowerShell 5.1 (unsupported)' {
        BeforeAll {
            # Static, throwaway encrypted PKCS#8 key committed as a fixture -- generated once via
            # RSA.ExportEncryptedPkcs8PrivateKeyPem on PowerShell 7 (password: 'winps51-static-test-password').
            # Windows PowerShell 5.1 cannot generate this itself (see the BeforeAll above), so a static
            # PEM is the only way to exercise the "BEGIN ENCRYPTED PRIVATE KEY" branch there. It is never
            # decrypted on 5.1 -- New-PfbJwtToken.ps1's PS 5.1 branch throws before any decrypt is attempted,
            # so the PEM only needs to be valid base64 with the right header, not a live secret.
            $script:staticEncryptedKeyPem = @'
-----BEGIN ENCRYPTED PRIVATE KEY-----
MIIFNjBgBgkqhkiG9w0BBQ0wUzAyBgkqhkiG9w0BBQwwJQQQl6/6NCWUf3PyE3qA
zpcgqQIDAYagMAwGCCqGSIb3DQIJBQAwHQYJYIZIAWUDBAEqBBBZxxr7x1OFInb/
Rk/mwl0dBIIE0Jedoi5hKGU2kByyH9yP++9cw6BZc8YXcH0Mo2Rg7lAuUPd8flWl
Ul7C1QWlhoqZVwvAgyUzn1Bf23Nd6kzi3MPPtGzEwq6NmpZMq9gxmcJv02HBK0vq
7f0QXYKnx8Kd2GgVP3dKhOlLCITVk89ZR/O55c2eYIE1Trnh2d7Ec428Iiw/obF4
yeobWLWgzpojaBupBgRgvTEARTkJk2PfKTZbt3NL7UMdCoaS4f2GTitLLbZpUDBU
jysez+N82Bl2th543zyJdcT7zgeM1EwItXvo6ZBPdKWMYozj3ZgJd8kcikYRFoTe
0gDNT/WRAjAV6rWticjOPxdnaLYp3CdVnsDeSooa+LwV9OyLCqVLM2JNMYcccSCn
QVwGySnmSb5K/psRaCAgYnFgBiS5RZmKpDi14Ir2rgrG09GS1xHjd/nW+m+dFnoW
0CQOuSX7CRlwzBsV9kt4WHkd54/63Rk8292ifa3ESPVbkvZvEa2GjSIrQ4ksKsTf
8xzrKqgCG5hVVxYhTIWDP7WaJ38MK9XnUzlZJZP0AMZgUUEr/kqNt/cDJfaozyVI
3jJEhE8Y7eokmZyNIm/zzMzRpiVB3J3ayk6sV/vGqautw8N3KaTi6fOE55tLkB9g
NdtGiWCHtOOVN7t9/fG+WIGW2Hd8GAVr+Y61IA3mXFjt1wXI4rM2NUP2xvRfqEff
94/43ijbRSD3n4xgRQDh7PaLXji8+jzA1BS5svwyWQQqNu+6avNeVtVQNQ1WU7vQ
fzFpmmaqEJHwTh5o5c1dRVEnLQdU7uQf/k0NqMYGfBSoX3nnLjAN8LYWwpo1kTIN
W75vDvRajDDzjGBh1DMFMnk0AvuqAVv6sL/Zf5PnHALH37DoBDAFsC87djXogGz4
C/V+vW0qOT02r5FAetOpjVz4+Ej39eemdI+d03VHB2tzW4NAlsAsW0DsgVaWGfsd
CCx9VXGSf/myDkbpsCZmZ9ze/01VR97xaIs3noUGBFF41urSq/5Z3rEYv1sAcdBL
1B6yOH2LPel4jdd10KzG22TY2Pnv9yfGF4ei9bAsHZOEq1Y8dpwhIb4XDSqiuiyJ
kea3j9y4Cyv+7BHvZUjY3jGYrs6Nxdbrt58lhey67qd3XOc1OooGnDIMQE420r3J
a+zr0Axy5kJiRnYyHAUkpQmXb8uRuUTw/utQINQ4eUTqToroNTODA0KcWZ7vKr6h
rUpwazMEDiIKTLX952nDLifIn0yE+lSw3WzW1nrdy/mlFY2ZreKiTOAVvmfnFnNe
3RhuKA80slrWT4PAoXC1fkf/mhR3kXcIpKCTsq/M32eq9Ubp1LUHwL2+2F0fm5mu
Y4mqypX6UHr61GhgsuxmiIVAmVWxIV8lYBNo5VEcCu2greCwuuEA8NVpsViQmgX+
4cLB9VQ6zxEN5kLeJbSJYe2GaebKvFVOU/ArXwC2q+awHw19koVlscXsZkOiGtgJ
ino3txqi9mxJ9HwreqLR3k7M8lLgYoH+1k+1bh/FXL5PV9yLqzpnPFh0Fmsp4vyb
2uPxEtMVMeJ3yICYeVwLJ37lKTMHFxw07J3vBeiL3RFOQarqd16ygKOXLo4MHFnx
/h1snXLa+AhvStCVR+BRHyzkqhMr7FPtMNlW3Q7HpbEEJ9K7pJXlOYdj
-----END ENCRYPTED PRIVATE KEY-----
'@
            $script:staticEncryptedKeyPath = Join-Path $TestDrive 'winps51-static-encrypted-key.pem'
            Set-Content -Path $script:staticEncryptedKeyPath -Value $script:staticEncryptedKeyPem -NoNewline
        }

        It 'throws a clear PowerShell 7+ error instead of a raw RuntimeException' -Skip:($PSVersionTable.PSVersion.Major -ge 6) {
            $securePassword = ConvertTo-SecureString 'winps51-static-test-password' -AsPlainText -Force
            $keyPathParam = $script:staticEncryptedKeyPath

            {
                InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                    keyPathParam   = $keyPathParam
                    securePassword = $securePassword
                } {
                    New-PfbJwtToken -KeyId 'key-1' -ClientId 'client-1' -Issuer 'myapp' `
                        -Username 'pureuser' -PrivateKeyFile $keyPathParam -PrivateKeyPassword $securePassword
                }
            } | Should -Throw -ExpectedMessage '*PowerShell 7+*'
        }
    }
}
