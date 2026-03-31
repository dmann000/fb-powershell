function Get-PfbFileSystemSnapshotPolicy {
    <#
    .SYNOPSIS
        Retrieves policies associated with file system snapshots on the FlashBlade.
    .DESCRIPTION
        Returns the mapping between file system snapshots and their attached
        policies. Can be filtered by policy name/ID or snapshot (member) name/ID.
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
        Get-PfbFileSystemSnapshotPolicy
        Returns all snapshot-to-policy mappings.
    .EXAMPLE
        Get-PfbFileSystemSnapshotPolicy -MemberName "fs01.snap1"
        Returns all policies attached to snapshot 'fs01.snap1'.
    .EXAMPLE
        Get-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly"
        Returns all snapshots that have the 'replication-hourly' policy.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-snapshots/policies' -QueryParams $queryParams -AutoPaginate
    }
}
