function New-PfbPresetWorkload {
    <#
    .SYNOPSIS
        Creates a new workload preset on the FlashBlade.
    .DESCRIPTION
        Defines a parameterized template that workloads can be instantiated from. The body
        schema (PresetWorkloadPost) is heavily nested (directory_configurations,
        placement_configurations, platform_features are required; export/QoS/quota/snapshot
        configurations are optional). Pass the full body via -Attributes — the typed surface
        would be too large to be useful.
    .PARAMETER Name
        Preset name(s) to create.
    .PARAMETER Attributes
        Full PresetWorkloadPost body. Required nested sections:
          - directory_configurations  (1-20 items)
          - placement_configurations  (exactly 1 item)
          - platform_features         (exactly 1 item)
        Optional sections: description, export_configurations, parameters,
        periodic_replication_configurations, qos_configurations, quota_configurations,
        snapshot_configurations.
    .PARAMETER SkipVerifyDeployable
        Skip verification that the preset is deployable on the FB at create time.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        $preset = @{
            description              = 'Analytics workload template'
            directory_configurations = @(@{ name = 'data'; path_template = '/{workload_name}/data' })
            placement_configurations = @(@{ name = 'default' })
            platform_features        = @(@{ name = 'file' })
        }
        New-PfbPresetWorkload -Name 'analytics-template' -Attributes $preset
    .NOTES
        <!-- PfbContext (generated; do not edit) -->
        Context requirement (POST /presets/workload): this cmdlet targets a fleet-scoped resource
        and requires a bare fleet context. Set one with
        Set-PfbContext -Context <fleet> -Kind Fleet, or scope a single call with
        Invoke-PfbInContext. Get the fleet name from Get-PfbFleet.
        <!-- /PfbContext -->
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [switch]$SkipVerifyDeployable,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'names' = $Name -join ',' }
    if ($SkipVerifyDeployable) { $queryParams['skip_verify_deployable'] = 'true' }

    if ($PSCmdlet.ShouldProcess(($Name -join ', '), 'Create workload preset')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'presets/workload' -QueryParams $queryParams -Body $Attributes
    }
}
