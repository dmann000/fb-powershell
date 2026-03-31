function New-PfbNodeGroupNode {
    <#
    .SYNOPSIS
        Adds a node to a FlashBlade node group.
    .DESCRIPTION
        The New-PfbNodeGroupNode cmdlet creates an association between a node and a node
        group on the connected Pure Storage FlashBlade. This assigns the specified node
        to the target group for workload placement purposes.
    .PARAMETER GroupName
        The name of the node group to add the node to.
    .PARAMETER MemberName
        The name of the node to add to the group.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNodeGroupNode -GroupName "analytics-group" -MemberName "CH1.FB1"

        Adds node CH1.FB1 to the analytics-group node group.
    .EXAMPLE
        New-PfbNodeGroupNode -GroupName "high-perf-group" -MemberName "CH1.FB2" -WhatIf

        Shows what would happen without adding the node to the group.
    .EXAMPLE
        New-PfbNodeGroupNode -GroupName "default-group" -MemberName "CH1.FB3"

        Adds node CH1.FB3 to the default-group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$GroupName,
        [Parameter(Mandatory)] [string]$MemberName,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    $queryParams['group_names']  = $GroupName
    $queryParams['member_names'] = $MemberName

    $target = "${GroupName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add node to node group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'node-groups/nodes' -QueryParams $queryParams
    }
}
