function Get-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Retrieves policy file system replica link associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbPolicyFileSystemReplicaLink cmdlet returns the cross-reference between
        policies and file system replica links on the connected Pure Storage FlashBlade.
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
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink

        Retrieves all policy file system replica link associations.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap"

        Retrieves replica link associations for the specified policy.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink -Limit 10

        Retrieves up to 10 policy replica link associations.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams -AutoPaginate
}
