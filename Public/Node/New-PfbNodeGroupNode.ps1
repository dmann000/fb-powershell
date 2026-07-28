function New-PfbNodeGroupNode {
    <#
    .SYNOPSIS
        Adds a node to a FlashBlade node group.
    .DESCRIPTION
        The New-PfbNodeGroupNode cmdlet creates an association between a node and a node
        group on the connected Pure Storage FlashBlade. This assigns the specified node
        to the target group for workload placement purposes.
    .PARAMETER GroupName
        The name of the node group to add the node to. Sent as the `node_group_names` query
        parameter.
    .PARAMETER GroupId
        The ID of the node group to add the node to. Sent as the `node_group_ids` query
        parameter.
    .PARAMETER MemberName
        The name of the node to add to the group. Sent as the `node_names` query parameter.
    .PARAMETER MemberId
        The ID of the node to add to the group. Sent as the `node_ids` query parameter.
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
    .EXAMPLE
        New-PfbNodeGroupNode -GroupId "10314f42-020d-7080-8013-000ddt400020" -MemberId "10314f42-020d-7080-8013-000ddt400005"

        Adds the node identified by ID to the node group identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        # -GroupName/-GroupId and -MemberName/-MemberId are plain optional parameters rather
        # than parameter sets -- see New-PfbNetworkInterfaceTlsPolicy.ps1 for the identical
        # shape and rationale (no request body here to multiply a selector axis against).
        [Parameter()] [string]$GroupName,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$GroupId,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    # Wire-correctness fix: POST /node-groups/nodes documents node_group_ids/node_group_names
    # and node_ids/node_names. This cmdlet previously sent group_names/member_names, which the
    # array silently ignored -- neither -GroupName nor -MemberName had any effect.
    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('GroupName'))  { $queryParams['node_group_names'] = $GroupName }
    if ($PSBoundParameters.ContainsKey('GroupId'))    { $queryParams['node_group_ids']   = $GroupId }
    if ($PSBoundParameters.ContainsKey('MemberName')) { $queryParams['node_names']       = $MemberName }
    if ($PSBoundParameters.ContainsKey('MemberId'))   { $queryParams['node_ids']         = $MemberId }

    $groupTarget  = if ($PSBoundParameters.ContainsKey('GroupName')) { $GroupName } else { $GroupId }
    $memberTarget = if ($PSBoundParameters.ContainsKey('MemberName')) { $MemberName } else { $MemberId }
    $target = "${groupTarget}:${memberTarget}"

    if ($PSCmdlet.ShouldProcess($target, 'Add node to node group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'node-groups/nodes' -QueryParams $queryParams
    }
}
