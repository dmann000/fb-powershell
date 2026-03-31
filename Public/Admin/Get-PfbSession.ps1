function Get-PfbSession {
    <#
    .SYNOPSIS
        Retrieves active sessions from the FlashBlade.
    .DESCRIPTION
        The Get-PfbSession cmdlet returns active administrator and API sessions from the
        connected Pure Storage FlashBlade. Sessions represent authenticated connections
        to the array management interface. Results support filtering, sorting, and pagination.
    .PARAMETER Name
        One or more session names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more session IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "user_interface='CLI'").
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'start_time' or 'start_time-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSession

        Returns all active sessions on the connected FlashBlade.
    .EXAMPLE
        Get-PfbSession -Filter "user_interface='GUI'" -Limit 5

        Retrieves up to 5 active GUI sessions.
    .EXAMPLE
        Get-PfbSession -Sort 'start_time-' -Limit 10

        Retrieves the 10 most recently started sessions.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'sessions' -QueryParams $queryParams -AutoPaginate
    }
}
