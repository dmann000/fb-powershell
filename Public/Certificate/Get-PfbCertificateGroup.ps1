function Get-PfbCertificateGroup {
    <#
    .SYNOPSIS
        Retrieves certificate groups from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbCertificateGroup cmdlet returns certificate group objects configured on the
        FlashBlade. Certificate groups organize related certificates for use with directory
        services and other TLS-enabled features. Results support filtering, sorting, and pagination.
    .PARAMETER Name
        One or more certificate group names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more certificate group IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., 'name=''ad-cert-group''').
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbCertificateGroup

        Returns all certificate groups configured on the connected FlashBlade.
    .EXAMPLE
        Get-PfbCertificateGroup -Name 'ad-cert-group'

        Retrieves the certificate group named 'ad-cert-group'.
    .EXAMPLE
        'ad-cert-group', 'ldap-cert-group' | Get-PfbCertificateGroup

        Retrieves multiple certificate groups by piping their names to the cmdlet.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'certificate-groups' -QueryParams $queryParams -AutoPaginate
    }
}
