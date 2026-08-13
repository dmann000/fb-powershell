function Remove-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Detaches a policy from a file system replica link on the FlashBlade.
    .DESCRIPTION
        Removes the association between a policy and a file system replica link by
        specifying the policy (by name or ID) and the replica link member ID.

        This endpoint selects members by ID only: `member_ids` is a declared query
        parameter and `member_names` is not. A detach must identify both a policy and a
        member, so -MemberId is required; this cmdlet issues no detach scoped to a policy
        alone.

        The selector rules are enforced at runtime rather than by parameter sets, which
        would multiply the published syntax without adding reachable combinations.
    .PARAMETER PolicyName
        The name of the policy to detach, sent as `policy_names`. Mutually exclusive with
        -PolicyId; one of the two is required.
    .PARAMETER PolicyId
        The ID of the policy to detach, sent as `policy_ids`. Mutually exclusive with
        -PolicyName; one of the two is required.
    .PARAMETER MemberId
        The ID of the replica link to detach the policy from, sent as the declared
        `member_ids` query parameter. Required: it is the only member selector this
        endpoint declares.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names, sent as the endpoint's declared `remote_names`
        query parameter. It qualifies a request that -PolicyName/-PolicyId and -MemberId
        have already identified; it is never an identity of its own. Mutually exclusive
        with -RemoteId: the API declares remote_names and remote_ids as alternative ways to
        name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs, sent as the declared `remote_ids` query parameter and
        qualifying the request the same way -RemoteName does. Mutually exclusive with
        -RemoteName.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -MemberId "def-456"
        Detaches the 'repl-daily' policy from the replica link with that ID.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyId "abc-123" -MemberId "def-456"
        Detaches a policy from a replica link using IDs.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-hourly" -MemberId "def-456" -Confirm:$false
        Detaches the policy without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [ValidateNotNullOrEmpty()] [string]$PolicyName,
        [Parameter()] [ValidateNotNullOrEmpty()] [string]$PolicyId,
        [Parameter()] [ValidateNotNullOrEmpty()] [string]$MemberId,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteName,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteId,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($PolicyName -and $PolicyId) {
        throw '-PolicyName and -PolicyId cannot be used together: policy_names and policy_ids are mutually exclusive.'
    }
    if (-not $PolicyName -and -not $PolicyId) {
        throw 'A policy must be identified: supply -PolicyName or -PolicyId.'
    }
    if (-not $MemberId) {
        throw 'A replica link member must be identified: supply -MemberId. This endpoint declares no member_names filter, so omitting -MemberId would detach the policy from every member.'
    }
    if ($RemoteName -and $RemoteId) {
        throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    $queryParams['member_ids'] = $MemberId
    # remote_names and remote_ids are assigned inline rather than through
    # Add-PfbCommonQueryParams: they are replication-family keys, not common ones.
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId)   { $queryParams['remote_ids']   = $RemoteId -join ',' }

    # The target names only what identifies the deletion: the policy and the member. The
    # remote selectors narrow it further, so they are shown as a qualifier and can never
    # stand in for the identity.
    $policyLabel = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $target = "${policyLabel}:${MemberId}"
    if ($RemoteName)   { $target = "$target (remote $($RemoteName -join ','))" }
    elseif ($RemoteId) { $target = "$target (remote $($RemoteId -join ','))" }

    if ($PSCmdlet.ShouldProcess($target, 'Detach policy from replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams
    }
}
