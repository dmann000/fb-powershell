function Get-PfbCertificateGroupCertificate {
    <#
    .SYNOPSIS
        Retrieves certificates associated with certificate groups from the FlashBlade.
    .DESCRIPTION
        The Get-PfbCertificateGroupCertificate cmdlet returns the certificate-to-group membership
        relationships configured on the FlashBlade. This shows which certificates belong to which
        certificate groups. Results support filtering, sorting, and pagination.

        Selectors on this endpoint are resource-specific: use -CertificateName to select by
        certificate name (wire key 'certificate_names') and -CertificateGroupId to select by
        certificate group ID (wire key 'certificate_group_ids'). The endpoint does not accept
        the generic 'names' or 'ids' query keys.
    .PARAMETER CertificateName
        One or more certificate names to retrieve group memberships for. Accepts pipeline input.
    .PARAMETER CertificateGroupId
        One or more certificate group IDs to retrieve certificate memberships for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'group.name' or 'certificate.name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbCertificateGroupCertificate

        Returns all certificate-to-group memberships on the connected FlashBlade.
    .EXAMPLE
        Get-PfbCertificateGroupCertificate -CertificateName 'management'

        Retrieves the group memberships of the 'management' certificate.
    .EXAMPLE
        Get-PfbCertificateGroupCertificate -CertificateGroupId '10314f42-020d-7080-8013-000ddd11003d'

        Retrieves the certificate memberships of the specified certificate group.
    .EXAMPLE
        Get-PfbCertificateGroupCertificate -Filter "group.name='ad-cert-group'" -Limit 10

        Retrieves up to 10 certificate memberships filtered by group name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        # Within this family, the cross-endpoint chain Get-PfbCertificate | Get-PfbCertificateGroupCertificate
        # cannot filter correctly: a producer's bare `name` bound to -CertificateName / `certificate_names`
        # is the defect because `name` means different things by endpoint and metadata cannot identify
        # its producer, so no correct generic binding exists. An undeclared or non-matching query key
        # returns HTTP 200 with the unfiltered collection, so the guard's loud failure is best. Do NOT
        # remove it or add an alias: that flips WrongScalar to Bound while sending the wrong name;
        # revisit only if the consumer can establish its producer, which metadata alone cannot. Issue #90.
        [Parameter(ParameterSetName = 'ByCertificateName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$CertificateName,
        [Parameter(ParameterSetName = 'ByCertificateGroupId')] [string[]]$CertificateGroupId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allCertificateNames = [System.Collections.Generic.List[string]]::new()
        $allCertificateGroupIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $CertificateName -ParameterName 'CertificateName' -Hint (
            'Pipe the certificate name instead, e.g. Get-PfbCertificate | ' +
            'Select-Object -ExpandProperty name | Get-PfbCertificateGroupCertificate, ' +
            'or pass -CertificateName explicitly, or -CertificateGroupId if you meant to filter by group.')
        if ($CertificateName)    { foreach ($n in $CertificateName)    { $allCertificateNames.Add($n) } }
        if ($CertificateGroupId) { foreach ($i in $CertificateGroupId) { $allCertificateGroupIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allCertificateNames.Count -gt 0) {
            $queryParams['certificate_names'] = $allCertificateNames -join ','
        }
        if ($allCertificateGroupIds.Count -gt 0) {
            $queryParams['certificate_group_ids'] = $allCertificateGroupIds -join ','
        }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'certificate-groups/certificates' -QueryParams $queryParams -AutoPaginate
    }
}
