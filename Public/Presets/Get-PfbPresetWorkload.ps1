function Get-PfbPresetWorkload {
    <#
    .SYNOPSIS
        Retrieves workload presets from the FlashBlade.
    .DESCRIPTION
        Returns one or more workload presets. A preset defines a parameterized template
        of storage resources (directories, exports, quotas, snapshots, placement, QoS, etc.)
        that workloads can be instantiated from via New-PfbWorkload.
    .PARAMETER Name
        One or more preset names to retrieve.
    .PARAMETER Id
        One or more preset IDs to retrieve.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbPresetWorkload
    .EXAMPLE
        Get-PfbPresetWorkload -Name 'analytics-template'
    .NOTES
        <!-- PfbContext (generated; do not edit) -->
        Context requirement (GET /presets/workload): this cmdlet targets a
        fleet-scoped resource, but reads on it are narrower than the
        requirement. An unfiltered list works with NO context, served from
        the array's locally replicated copy. Filtering by name or id needs a
        bare fleet context, because that local copy is list-only: set one
        with Set-PfbContext -Context <fleet> -Kind Fleet, or scope a single
        call with Invoke-PfbInContext. Get the fleet name from Get-PfbFleet.
        <!-- /PfbContext -->
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'presets/workload' -QueryParams $queryParams
    }
}
