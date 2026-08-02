function Set-PfbWorkloadTag {
    <#
    .SYNOPSIS
        Sets (creates or updates) tags on FlashBlade workloads.
    .DESCRIPTION
        PUT batch upsert of tags on the specified workloads. Pass the tag set as an array of
        hashtables. Each tag is { key, value, namespace? }.
    .PARAMETER ResourceName
        Workload name(s) to tag.
    .PARAMETER ResourceId
        Workload ID(s) to tag.
    .PARAMETER Tags
        Array of tag hashtables (1-30 items). Each: @{ key = '...'; value = '...'; namespace = '...' }
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Set-PfbWorkloadTag -ResourceName wl1 -Tags @(
            @{ key='team';  value='analytics'; namespace='default' },
            @{ key='env';   value='prod';      namespace='default' }
        )
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$ResourceName,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$ResourceId,

        [Parameter(Mandatory)]
        [ValidateCount(1, 30)]
        [hashtable[]]$Tags,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($ResourceName) { $queryParams['resource_names'] = $ResourceName -join ',' }
    if ($ResourceId)   { $queryParams['resource_ids']   = $ResourceId -join ',' }

    if ($PSCmdlet.ShouldProcess(($ResourceName + $ResourceId -join ', '), "Apply $($Tags.Count) tag(s)")) {
        # $Tags goes over as the body unmodified: this endpoint's body IS the tag array, not
        # an object wrapping one. Serialisation happens in the shared path, which uses
        # ConvertTo-Json -InputObject -- so the one-element array stays an array. That is the
        # same guarantee the local ConvertTo-Json deleted here used to provide; the
        # single-tag test asserting it is unchanged and still passes through this path.
        Invoke-PfbApiRequest -Array $Array -Method PUT -Endpoint 'workloads/tags/batch' `
            -Body $Tags -QueryParams $queryParams
    }
}
