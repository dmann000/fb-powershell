function New-PfbCertificateSigningRequest {
    <#
    .SYNOPSIS
        Creates a certificate signing request (CSR) on a FlashBlade array.
    .DESCRIPTION
        The New-PfbCertificateSigningRequest cmdlet generates a new CSR on the connected
        Pure Storage FlashBlade. The CSR can be submitted to a certificate authority for signing.
    .PARAMETER Name
        The name of the certificate to generate a CSR for.
    .PARAMETER Attributes
        A hashtable of CSR attributes such as common_name, organization, and country.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbCertificateSigningRequest -Name "cert-prod" -Attributes @{ common_name = "fb.example.com" }

        Generates a CSR for the specified certificate with the given common name.
    .EXAMPLE
        New-PfbCertificateSigningRequest -Name "cert-prod" -Attributes @{ common_name = "fb.example.com"; organization = "Acme" }

        Generates a CSR with organization details.
    .EXAMPLE
        New-PfbCertificateSigningRequest -Name "cert-test" -Attributes @{} -WhatIf

        Shows what would happen without actually generating the CSR.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create certificate signing request')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'certificates/certificate-signing-requests' -Body $Attributes -QueryParams $q
    }
}
