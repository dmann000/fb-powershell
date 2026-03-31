function New-PfbCertificateCertificateGroup {
    <#
    .SYNOPSIS
        Associates a certificate with a certificate group on a FlashBlade array.
    .DESCRIPTION
        The New-PfbCertificateCertificateGroup cmdlet creates an association between a
        certificate and a certificate group on the connected Pure Storage FlashBlade.
    .PARAMETER CertificateName
        The certificate name.
    .PARAMETER CertificateGroupName
        The certificate group name.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbCertificateCertificateGroup -CertificateName "cert-prod" -CertificateGroupName "group-prod"

        Associates the certificate with the certificate group.
    .EXAMPLE
        New-PfbCertificateCertificateGroup -CertificateName "cert-new" -CertificateGroupName "group-prod" -WhatIf

        Shows what would happen without actually creating the association.
    .EXAMPLE
        New-PfbCertificateCertificateGroup -CertificateName "cert-ca" -CertificateGroupName "group-tls"

        Associates the CA certificate with the TLS group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$CertificateName,
        [Parameter()] [string]$CertificateGroupName,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($CertificateName) { $queryParams['certificate_names'] = $CertificateName }
    if ($CertificateGroupName) { $queryParams['certificate_group_names'] = $CertificateGroupName }

    $target = "${CertificateName}:${CertificateGroupName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add certificate to certificate group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'certificates/certificate-groups' -QueryParams $queryParams
    }
}
