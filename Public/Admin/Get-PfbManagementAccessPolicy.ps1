function Get-PfbManagementAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves FlashBlade management access policies.
    .DESCRIPTION
        The Get-PfbManagementAccessPolicy cmdlet returns one or more management access policies
        from the connected Pure Storage FlashBlade. Results can be filtered by name, ID, or a
        server-side filter expression. Supports pipeline input for batch lookups and automatic
        pagination.
    .PARAMETER Name
        One or more management access policy names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more management access policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "name='full-access'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbManagementAccessPolicy

        Retrieves all management access policies from the connected FlashBlade.
    .EXAMPLE
        Get-PfbManagementAccessPolicy -Name "full-access"

        Retrieves the management access policy named "full-access".
    .EXAMPLE
        Get-PfbManagementAccessPolicy -Filter "name='readonly*'" -Limit 10

        Retrieves up to 10 management access policies matching the filter.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'management-access-policies' -QueryParams $queryParams -AutoPaginate
    }
}
