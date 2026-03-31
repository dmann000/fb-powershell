function Get-PfbFileSystemAuditPolicy {
    <#
    .SYNOPSIS
        Retrieves audit policies associated with file systems on the FlashBlade.
    .DESCRIPTION
        Returns the mapping between file systems and their attached audit policies.
        Can be filtered by policy name/ID or file system (member) name/ID.
    .PARAMETER PolicyName
        One or more audit policy names to filter by.
    .PARAMETER PolicyId
        One or more audit policy IDs to filter by.
    .PARAMETER MemberName
        One or more file system names to filter by.
    .PARAMETER MemberId
        One or more file system IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemAuditPolicy
        Returns all file-system-to-audit-policy mappings.
    .EXAMPLE
        Get-PfbFileSystemAuditPolicy -MemberName "fs01"
        Returns all audit policies attached to file system 'fs01'.
    .EXAMPLE
        Get-PfbFileSystemAuditPolicy -PolicyName "audit-all" -MemberName "fs01"
        Checks whether the 'audit-all' policy is attached to 'fs01'.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/audit-policies' -QueryParams $queryParams -AutoPaginate
    }
}
