function Get-PfbPolicyAllMember {
    <#
    .SYNOPSIS
        Retrieves unified policy member associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbPolicyAllMember cmdlet returns a read-only unified view of all policy
        member associations across all policy types on the connected Pure Storage FlashBlade.

        -MemberName is retained here deliberately. The replica-link membership cmdlets lost
        theirs because `member_names` is absent from their endpoints' published parameter
        lists, but `GET /policies-all/members` does declare `member_names` (from REST 2.2,
        the version that introduced the endpoint), so the filter is honoured on the wire.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more member names to filter by. Sent as the spec-declared `member_names`
        query parameter, which this endpoint -- unlike its replica-link siblings -- honours.
    .PARAMETER MemberId
        One or more member IDs to filter by.
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
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    if ($MemberType) { $queryParams['member_types'] = $MemberType -join ',' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies-all/members' -QueryParams $queryParams -AutoPaginate
}
