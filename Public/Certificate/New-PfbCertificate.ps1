function New-PfbCertificate {
    <#
    .SYNOPSIS
        Creates or imports an SSL/TLS certificate on a Pure Storage FlashBlade.
    .DESCRIPTION
        The New-PfbCertificate cmdlet creates or imports a certificate on the FlashBlade.
        The Attributes hashtable must contain the certificate data such as the PEM-encoded
        certificate body, private key, and optionally an intermediate certificate chain.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER Name
        The name to assign to the certificate on the FlashBlade.
    .PARAMETER Attributes
        A hashtable containing certificate data. Supported keys include 'certificate' (PEM-encoded
        certificate body), 'key' (PEM-encoded private key), and 'intermediate_certificate'
        (PEM-encoded intermediate CA chain).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbCertificate -Name 'web-cert' -Attributes @{ certificate = $certPem; key = $keyPem }

        Imports a certificate and its private key with the name 'web-cert'.
    .EXAMPLE
        $attrs = @{ certificate = $certPem; key = $keyPem; intermediate_certificate = $chainPem }
        New-PfbCertificate -Name 'app-cert' -Attributes $attrs

        Imports a certificate with a full chain including the intermediate CA certificate.
    .EXAMPLE
        New-PfbCertificate -Name 'test-cert' -Attributes @{ certificate = $certPem; key = $keyPem } -WhatIf

        Shows what would happen when importing a certificate without actually creating it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create certificate')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'certificates' -Body $Attributes -QueryParams $queryParams
    }
}
