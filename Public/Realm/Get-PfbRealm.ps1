function Get-PfbRealm {
    <#
    .SYNOPSIS
        Retrieves FlashBlade realms.
    .DESCRIPTION
        Returns one or more realms from the FlashBlade array. Supports filtering
        by name, ID, or advanced filter expressions. Auto-paginates by default.
    .PARAMETER Name
        One or more realm names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more realm IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression (e.g., "name='realm1'" or "destroyed").
    .PARAMETER Sort
        Sort field and direction (e.g., "name", "created-" for descending).
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Destroyed
        Include destroyed realms.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbRealm
    .EXAMPLE
        Get-PfbRealm -Name "realm1", "realm2"
    .EXAMPLE
        "realm1" | Get-PfbRealm
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
        [switch]$Destroyed,

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
        if ($Destroyed)            { $queryParams['destroyed']  = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'realms' -QueryParams $queryParams -AutoPaginate
    }
}
