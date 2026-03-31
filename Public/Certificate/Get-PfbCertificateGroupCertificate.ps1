function Get-PfbCertificateGroupCertificate {
    <#
    .SYNOPSIS
        Retrieves certificates associated with certificate groups from the FlashBlade.
    .DESCRIPTION
        The Get-PfbCertificateGroupCertificate cmdlet returns the certificate-to-group membership
        relationships configured on the FlashBlade. This shows which certificates belong to which
        certificate groups. Results support filtering, sorting, and pagination.
    .PARAMETER Name
        One or more certificate group names to retrieve certificate memberships for. Accepts pipeline input.
    .PARAMETER Id
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
        Get-PfbCertificateGroupCertificate -Name 'ad-cert-group'

        Retrieves certificates that belong to the 'ad-cert-group' certificate group.
    .EXAMPLE
        Get-PfbCertificateGroupCertificate -Filter "group.name='ad-cert-group'" -Limit 10

        Retrieves up to 10 certificate memberships filtered by group name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']    = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'certificate-groups/certificates' -QueryParams $queryParams -AutoPaginate
    }
}
