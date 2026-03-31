function Remove-PfbNodeGroupNode {
    <#
    .SYNOPSIS
        Removes a node from a FlashBlade node group.
    .DESCRIPTION
        The Remove-PfbNodeGroupNode cmdlet deletes the association between a node and a
        node group on the connected Pure Storage FlashBlade. This cmdlet has a high confirm
        impact and will prompt for confirmation by default.
    .PARAMETER GroupName
        The name of the node group to remove the node from.
    .PARAMETER MemberName
        The name of the node to remove from the group.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNodeGroupNode -GroupName "analytics-group" -MemberName "CH1.FB1"

        Removes node CH1.FB1 from the analytics-group after prompting for confirmation.
    .EXAMPLE
        Remove-PfbNodeGroupNode -GroupName "test-group" -MemberName "CH1.FB2" -Confirm:$false

        Removes the node from the group without prompting.
    .EXAMPLE
        Remove-PfbNodeGroupNode -GroupName "old-group" -MemberName "CH1.FB3"

        Removes node CH1.FB3 from the old-group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove node from node group')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'node-groups/nodes' -QueryParams $queryParams
    }
}
