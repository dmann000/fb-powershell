function Get-PfbAdmin {
    <#
    .SYNOPSIS
        Retrieves FlashBlade administrator accounts.
    .DESCRIPTION
        The Get-PfbAdmin cmdlet returns one or more administrator accounts from the connected
        Pure Storage FlashBlade. Results can be filtered by name, ID, or a server-side filter
        expression. Supports pipeline input for batch lookups and automatic pagination.
    .PARAMETER Name
        One or more administrator account names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more administrator account IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "role.name='array_admin'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of administrator entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAdmin

        Retrieves all administrator accounts from the connected FlashBlade.
    .EXAMPLE
        Get-PfbAdmin -Name "pureuser"

        Retrieves the administrator account named "pureuser".
    .EXAMPLE
        Get-PfbAdmin -Filter "role.name='array_admin'" -Limit 5

        Retrieves up to 5 administrator accounts with the array_admin role.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'admins' -QueryParams $queryParams -AutoPaginate
    }
}
