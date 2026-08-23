function Get-PfbRemoteArray {
    <#
    .SYNOPSIS
        Retrieves remote array configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRemoteArray cmdlet returns remote array information from the connected
        Pure Storage FlashBlade. Remote arrays represent other FlashBlade or FlashArray systems
        that are visible for replication or fleet operations.
    .PARAMETER Name
        One or more remote array names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more remote array IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='connected'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRemoteArray

        Retrieves all remote arrays from the connected FlashBlade.
    .EXAMPLE
        Get-PfbRemoteArray -Name "remote-dc2"

        Retrieves the remote array named "remote-dc2".
    .EXAMPLE
        Get-PfbRemoteArray -Filter "status='connected'" -Limit 20

        Retrieves up to 20 connected remote arrays.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [switch]$CurrentFleetOnly = $true,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        # current_fleet_only is a scope flag, not a selector, and is written on every path -- so
        # it must not count toward "a selector reached the query". Since #126 the CLASSIFICATION
        # is what enforces that: the key is on $script:PfbNonSelectorQueryKeys
        # (Private/PfbSelectorPolicyConstants.ps1) and the guard would behave identically below
        # the write. The placement is kept because moving it buys nothing and would need a
        # matching change to $allowedPostGuardWrite in
        # Tests/PfbEmptyPipelineGuardCoverage.Tests.ps1, which still allowlists this cmdlet by
        # name for writing a query key after its guard.
        #
        # One consequence of the placement, measured rather than assumed: because the guard runs
        # BEFORE the write, `@() | Get-PfbRemoteArray -CurrentFleetOnly` reaches the guard with an
        # EMPTY query and so takes the no-keys path -- verbose only, no warning. Below the write it
        # would warn on every empty-pipe call of this cmdlet, since current_fleet_only is always
        # present. Quiet is the better trade here; do not "fix" it by moving the guard.
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        if ($CurrentFleetOnly) { $queryParams['current_fleet_only'] = 'true' } else { $queryParams['current_fleet_only'] = 'false' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'remote-arrays' -QueryParams $queryParams -AutoPaginate
    }
}
