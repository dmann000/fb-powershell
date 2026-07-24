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
