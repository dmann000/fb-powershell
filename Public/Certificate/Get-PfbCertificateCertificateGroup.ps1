function Get-PfbCertificateCertificateGroup {
    <#
    .SYNOPSIS
        Retrieves certificate-to-certificate-group associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbCertificateCertificateGroup cmdlet returns the cross-reference between
        certificates and certificate groups on the connected Pure Storage FlashBlade.
    .PARAMETER CertificateName
        One or more certificate names to filter by.
    .PARAMETER CertificateGroupName
        One or more certificate group names to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbCertificateCertificateGroup

        Retrieves all certificate-to-group associations.
    .EXAMPLE
        Get-PfbCertificateCertificateGroup -CertificateName "cert-prod"

        Retrieves group associations for the specified certificate.
    .EXAMPLE
        Get-PfbCertificateCertificateGroup -CertificateGroupName "group-prod" -Limit 10

        Retrieves up to 10 certificate associations for the specified group.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$CertificateName,
        [Parameter()] [string[]]$CertificateGroupName,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($CertificateName) { $queryParams['certificate_names'] = $CertificateName -join ',' }
    if ($CertificateGroupName) { $queryParams['certificate_group_names'] = $CertificateGroupName -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'certificates/certificate-groups' -QueryParams $queryParams -AutoPaginate
}
