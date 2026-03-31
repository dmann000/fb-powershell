function Get-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Retrieves policies associated with file system replica links on the FlashBlade.
    .DESCRIPTION
        Returns the mapping between file system replica links and their attached policies.
        Can be filtered by policy name/ID or member (replica link) name/ID.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more replica link names to filter by.
    .PARAMETER MemberId
        One or more replica link IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy
        Returns all replica-link-to-policy mappings.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy -MemberName "fs01"
        Returns all policies attached to replica links for 'fs01'.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -MemberName "fs01"
        Checks whether the 'repl-daily' policy is attached to replica links for 'fs01'.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams -AutoPaginate
    }
}
