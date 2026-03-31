function Get-PfbNodeGroupNode {
    <#
    .SYNOPSIS
        Retrieves node membership within FlashBlade node groups.
    .DESCRIPTION
        The Get-PfbNodeGroupNode cmdlet returns the associations between node groups and
        their member nodes on the connected Pure Storage FlashBlade. Results can be filtered
        by group name, group ID, member name, or member ID.
    .PARAMETER GroupName
        One or more node group names to filter by.
    .PARAMETER GroupId
        One or more node group IDs to filter by.
    .PARAMETER MemberName
        One or more node (member) names to filter by.
    .PARAMETER MemberId
        One or more node (member) IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNodeGroupNode

        Retrieves all node group to node associations.
    .EXAMPLE
        Get-PfbNodeGroupNode -GroupName "analytics-group"

        Retrieves all nodes in the specified node group.
    .EXAMPLE
        Get-PfbNodeGroupNode -MemberName "CH1.FB1" -GroupName "default-group"

        Checks whether the specified node belongs to the given group.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$GroupName,
        [Parameter()] [string[]]$GroupId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($GroupName)  { $queryParams['group_names']  = $GroupName -join ',' }
    if ($GroupId)    { $queryParams['group_ids']    = $GroupId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    if ($Filter)     { $queryParams['filter']       = $Filter }
    if ($Sort)       { $queryParams['sort']         = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    try {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'node-groups/nodes' -QueryParams $queryParams -AutoPaginate
    }
    catch {
        if ($_ -match 'not supported' -or $_ -match 'Operation not permitted') {
            Write-Warning "Node groups are not supported on this FlashBlade model."
            return
        }
        throw
    }
}
