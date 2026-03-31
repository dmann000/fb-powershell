function Remove-PfbCertificateCertificateGroup {
    <#
    .SYNOPSIS
        Removes a certificate from a certificate group on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbCertificateCertificateGroup cmdlet removes the association between a
        certificate and a certificate group on the connected Pure Storage FlashBlade.
    .PARAMETER CertificateName
        The certificate name.
    .PARAMETER CertificateGroupName
        The certificate group name.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbCertificateCertificateGroup -CertificateName "cert-old" -CertificateGroupName "group-prod"

        Removes the certificate from the group after prompting.
    .EXAMPLE
        Remove-PfbCertificateCertificateGroup -CertificateName "cert-old" -CertificateGroupName "group-prod" -Confirm:$false

        Removes the association without prompting.
    .EXAMPLE
        Remove-PfbCertificateCertificateGroup -CertificateName "cert-expired" -CertificateGroupName "group-tls"

        Removes the expired certificate from the TLS group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove certificate from certificate group')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'certificates/certificate-groups' -QueryParams $queryParams
    }
}
