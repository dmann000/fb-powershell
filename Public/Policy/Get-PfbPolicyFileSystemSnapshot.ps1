function Get-PfbPolicyFileSystemSnapshot {
    <#
    .SYNOPSIS
        Retrieves file system snapshots associated with policies from the FlashBlade.
    .DESCRIPTION
        Returns the mapping between policies and file system snapshots. Can be
        filtered by policy name/ID or snapshot (member) name/ID to see which
        policies are applied to which snapshots.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more snapshot names to filter by.
    .PARAMETER MemberId
        One or more snapshot IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbPolicyFileSystemSnapshot
        Returns all policy-to-snapshot mappings.
    .EXAMPLE
        Get-PfbPolicyFileSystemSnapshot -PolicyName "replication-hourly"
        Returns all snapshots that have the 'replication-hourly' policy.
    .EXAMPLE
        Get-PfbPolicyFileSystemSnapshot -MemberName "fs01.snap1"
        Returns all policies applied to snapshot 'fs01.snap1'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
        if ($MemberName) { $queryParams['member_names']  = $MemberName -join ',' }
        if ($MemberId)   { $queryParams['member_ids']    = $MemberId -join ',' }
        if ($Filter)     { $queryParams['filter']        = $Filter }
        if ($Sort)       { $queryParams['sort']          = $Sort }
        if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/file-system-snapshots' -QueryParams $queryParams -AutoPaginate
    }
}
