function Get-PfbPolicyAllMember {
    <#
    .SYNOPSIS
        Retrieves unified policy member associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbPolicyAllMember cmdlet returns a read-only unified view of all policy
        member associations across all policy types on the connected Pure Storage FlashBlade.

        This endpoint declares both `member_names` and `member_ids`, so members can be
        selected by either, and it declares `remote_names` and `remote_ids` for the remote
        dimension of the members that have one.
    .PARAMETER PolicyName
        One or more policy names to filter by. Sent as `policy_names`.
    .PARAMETER PolicyId
        One or more policy IDs to filter by. Sent as `policy_ids`.
    .PARAMETER MemberName
        One or more member names to filter by. Sent as the declared `member_names` query
        parameter.
    .PARAMETER MemberId
        One or more member IDs to filter by. Sent as the declared `member_ids` query
        parameter.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names, sent as the declared `remote_names` query
        parameter. Mutually exclusive with -RemoteId: the API declares remote_names and
        remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs, sent as the declared `remote_ids` query parameter.
        Mutually exclusive with -RemoteName.
    .PARAMETER MemberType
        One or more member types to filter by (e.g. "file-systems", "object-store-users").
        Tab-completes the values documented as of this module's release, but the server's
        accepted set has grown across REST versions and may include newer values not offered
        here — any value is passed through as-is, not validated client-side.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPolicyAllMember

        Retrieves all policy member associations.
    .EXAMPLE
        Get-PfbPolicyAllMember -PolicyName "daily-snap"

        Retrieves all members of the specified policy.
    .EXAMPLE
        Get-PfbPolicyAllMember -MemberName "fs1" -Limit 20

        Retrieves up to 20 policy associations for the specified member.
    .EXAMPLE
        Get-PfbPolicyAllMember -MemberType "file-system-replica-links" -RemoteName "remote-fb"

        Queries replica-link members with remote_names=remote-fb.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()]
        [ArgumentCompleter({
            param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)
            @(
                'file-systems',
                'file-system-snapshots',
                'file-system-replica-links',
                'object-store-users',
                'object-store-accounts'
            ) | Where-Object { $_ -like "$WordToComplete*" }
        })]
        [string[]]$MemberType,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteName,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($PSBoundParameters.ContainsKey('RemoteName') -and $PSBoundParameters.ContainsKey('RemoteId')) {
        throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    if ($MemberType) { $queryParams['member_types'] = $MemberType -join ',' }
    # remote_names and remote_ids are assigned inline rather than through
    # Add-PfbCommonQueryParams: they are replication-family keys, not common ones.
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies-all/members' -QueryParams $queryParams -AutoPaginate
}
