function Remove-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Removes a policy from a file system replica link on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbPolicyFileSystemReplicaLink cmdlet removes the association between a
        policy and a file system replica link on the connected Pure Storage FlashBlade.

        `DELETE /policies/file-system-replica-links` declares no `member_names` query
        parameter. The former -MemberName was therefore dropped on the wire, turning a
        call that looked like a single removal into a removal of the policy from EVERY
        replica link. It has been removed so such a call now fails at parameter binding
        instead. -MemberId is the spec-declared member selector and is required here for
        the same reason: this cmdlet will not issue a policy-wide removal.

        The composite selector rules are enforced at runtime rather than by parameter sets,
        which would multiply the published syntax without adding reachable combinations.
    .PARAMETER PolicyName
        The policy name. Mutually exclusive with -PolicyId; one of the two is required.
    .PARAMETER PolicyId
        The policy ID. Mutually exclusive with -PolicyName; one of the two is required.
    .PARAMETER MemberId
        The file system replica link ID. Required: it is the only member identity this
        endpoint accepts, and without it the request would remove the policy from every
        member.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names, further narrowing the removal to replica links whose
        remote side is one of those arrays. A qualifier on -MemberId, never an identity of
        its own. Mutually exclusive with -RemoteId: the API declares remote_names and
        remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs, narrowing the removal the same way -RemoteName does.
        Mutually exclusive with -RemoteName.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberId "fsrl-1"

        Removes the policy association after prompting for confirmation.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberId "fsrl-1" -Confirm:$false

        Removes the association without prompting.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyId "pol-9" -MemberId "fsrl-2" -RemoteName "remote-fb"

        Removes the policy from that replica link only if its remote side is 'remote-fb'.
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
        throw 'A replica link member must be identified: supply -MemberId. This endpoint declares no member_names filter, so omitting -MemberId would remove the policy from every member.'
    }
    if ($RemoteName -and $RemoteId) {
        throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    $queryParams['member_ids'] = $MemberId
    # remote_names and remote_ids are assigned inline rather than through
    # Add-PfbCommonQueryParams: they are replication-family keys, not common ones.
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }

    # The target names only what identifies the deletion: the policy and the member. The
    # remote selectors narrow it further, so they are shown as a qualifier and can never
    # stand in for the identity.
    $policyLabel = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $target = "${policyLabel}:${MemberId}"
    if ($RemoteName) { $target = "$target (remote $($RemoteName -join ','))" }
    elseif ($RemoteId) { $target = "$target (remote $($RemoteId -join ','))" }

    if ($PSCmdlet.ShouldProcess($target, 'Remove policy from file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams
    }
}
