function Get-PfbAdminCache {
    <#
    .SYNOPSIS
        Retrieves admin cache entries from the FlashBlade.
    .DESCRIPTION
        The Get-PfbAdminCache cmdlet returns cached administrator entries from the connected
        Pure Storage FlashBlade. The admin cache stores authentication and authorization
        information for administrator accounts to improve login performance.
    .PARAMETER Name
        One or more admin cache entry names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more admin cache entry IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAdminCache

        Returns all admin cache entries on the connected FlashBlade.
    .EXAMPLE
        Get-PfbAdminCache -Name 'pureuser'

        Retrieves the admin cache entry for the administrator named 'pureuser'.
    .EXAMPLE
        Get-PfbAdminCache -Filter "role.name='array_admin'" -Limit 10

        Retrieves up to 10 admin cache entries filtered by role.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'admins/cache' -QueryParams $queryParams -AutoPaginate
    }
}
