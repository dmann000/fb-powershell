function Get-PfbServer {
    <#
    .SYNOPSIS
        Retrieves FlashBlade servers.
    .DESCRIPTION
        Returns one or more servers from the FlashBlade array. Supports filtering
        by name, ID, or advanced filter expressions. Auto-paginates by default.
        Server objects include name, id, created, dns, directory_services, and realms references.
    .PARAMETER Name
        One or more server names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more server IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression (e.g., "name='server1'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name", "created-" for descending).
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbServer

        Returns all servers on the FlashBlade.
    .EXAMPLE
        Get-PfbServer -Name "server1", "server2"

        Returns the servers named server1 and server2.
    .EXAMPLE
        "server1" | Get-PfbServer

        Retrieves server1 using pipeline input.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [switch]$TotalOnly,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']        = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'servers' -QueryParams $queryParams -AutoPaginate
    }
}
