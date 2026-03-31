function New-PfbNodeGroup {
    <#
    .SYNOPSIS
        Creates a new node group on a FlashBlade array.
    .DESCRIPTION
        The New-PfbNodeGroup cmdlet creates a new node group on the connected Pure Storage
        FlashBlade. Node groups organize nodes for workload placement and resource management.
        Supports ShouldProcess for -WhatIf and -Confirm.
    .PARAMETER Name
        The name for the new node group.
    .PARAMETER Attributes
        A hashtable of node group attributes for the new group.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNodeGroup -Name "analytics-group" -Attributes @{}

        Creates a new node group named analytics-group.
    .EXAMPLE
        New-PfbNodeGroup -Name "high-perf-group" -Attributes @{ priority = 'high' }

        Creates a new node group with custom attributes.
    .EXAMPLE
        New-PfbNodeGroup -Name "test-group" -Attributes @{} -WhatIf

        Shows what would happen without creating the node group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create node group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'node-groups' -Body $Attributes -QueryParams $q
    }
}
