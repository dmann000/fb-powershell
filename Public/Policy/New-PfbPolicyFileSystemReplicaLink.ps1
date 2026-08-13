function New-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Associates a policy with a file system replica link on a FlashBlade array.
    .DESCRIPTION
        The New-PfbPolicyFileSystemReplicaLink cmdlet creates an association between a policy
        and a file system replica link on the connected Pure Storage FlashBlade.

        The endpoint identifies the replica link by its local file system
        (`local_file_system_names`/`local_file_system_ids`) and remote side
        (`remote_names`/`remote_ids`). -MemberId is an additional independent selector mapped
        to the endpoint's `member_ids` query parameter. -LocalFileSystemName also accepts
        -MemberName as a backward-compatible alias, matching New-PfbFileSystemReplicaLinkPolicy.
    .PARAMETER PolicyName
        The policy name.
    .PARAMETER PolicyId
        The policy ID.
    .PARAMETER LocalFileSystemName
        The name of the local file system side of the replica link. Also accepts the alias
        -MemberName.
    .PARAMETER LocalFileSystemId
        The ID of the local file system side of the replica link.
    .PARAMETER MemberId
        The ID of the replica link member. Sent as the `member_ids` query parameter -- unlike
        -MemberName (removed: `member_names` is not a valid query parameter for this endpoint),
        `member_ids` is real and spec-declared.
    .PARAMETER RemoteName
        The name of the remote side of the replica link.
    .PARAMETER RemoteId
        The ID of the remote side of the replica link.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -LocalFileSystemName "fs1" -RemoteName "remote-fb"

        Associates the policy with the replica link identified by local file system and remote.
    .EXAMPLE
        New-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -LocalFileSystemName "fs1" -RemoteName "remote-fb" -WhatIf

        Shows what would happen without actually creating the association.
    .EXAMPLE
        New-PfbPolicyFileSystemReplicaLink -PolicyName "hourly-snap" -LocalFileSystemId "lfs-2" -RemoteId "remote-2"

        Associates the hourly snapshot policy with the specified replica link using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [Alias('MemberName')] [string]$LocalFileSystemName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [string]$LocalFileSystemId,
        [Parameter()] [string]$RemoteName,
        [Parameter()] [string]$RemoteId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($PSBoundParameters.ContainsKey('LocalFileSystemName')) { $queryParams['local_file_system_names'] = $LocalFileSystemName }
    if ($PSBoundParameters.ContainsKey('LocalFileSystemId'))   { $queryParams['local_file_system_ids']   = $LocalFileSystemId }
    if ($PSBoundParameters.ContainsKey('MemberId'))            { $queryParams['member_ids']              = $MemberId }
    if ($PSBoundParameters.ContainsKey('RemoteName'))          { $queryParams['remote_names']            = $RemoteName }
    if ($PSBoundParameters.ContainsKey('RemoteId'))            { $queryParams['remote_ids']              = $RemoteId }

    $target = "${PolicyName}:${LocalFileSystemName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add policy to file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams
    }
}
