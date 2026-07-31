function Get-PfbAlert {
    <#
    .SYNOPSIS
        Retrieves FlashBlade alerts.
    .PARAMETER Name
        One or more alert names to retrieve.
    .PARAMETER Id
        One or more alert IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Flagged
        Filter by flagged state.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbAlert
    .EXAMPLE
        Get-PfbAlert -Filter "state='open'"
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [Nullable[bool]]$Flagged,
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
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        if ($PSBoundParameters.ContainsKey('Flagged'))    { $queryParams['flagged'] = ([bool]$Flagged).ToString().ToLower() }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'alerts' -QueryParams $queryParams -AutoPaginate
    }
}
