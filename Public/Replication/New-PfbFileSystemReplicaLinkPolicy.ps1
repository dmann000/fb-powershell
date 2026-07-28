function New-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Attaches a policy to a file system replica link on the FlashBlade.
    .DESCRIPTION
        Associates an existing policy with a file system replica link by specifying
        both the policy and replica link (member) names or IDs.

        `POST /file-system-replica-links/policies` accepts `member_ids` but has no
        `member_names` query parameter at all -- it identifies the local side of the link by
        name via `local_file_system_names` instead. The cmdlet previously sent `-MemberName` as
        `member_names`, which this endpoint silently ignores, so name-based member selection
        could never have worked. -LocalFileSystemName is the corrected parameter; -MemberName
        is kept as a backward-compatible alias of it.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER LocalFileSystemName
        The name of the local file system side of the replica link to attach the policy to.
        Sent as the `local_file_system_names` query parameter. Also accepts the alias
        -MemberName.
    .PARAMETER LocalFileSystemId
        The ID of the local file system side of the replica link to attach the policy to.
    .PARAMETER MemberId
        The ID of the replica link member to attach the policy to.
    .PARAMETER RemoteId
        The ID of the remote array associated with the replica link.
    .PARAMETER RemoteName
        The name of the remote array associated with the replica link.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -LocalFileSystemName "fs01"
        Attaches the 'repl-daily' policy to the replica link for local file system 'fs01'.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyId "abc-123" -MemberId "def-456"
        Attaches a policy to a replica link using IDs.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-hourly" -LocalFileSystemName "fs02" -Confirm:$false
        Attaches the policy without prompting for confirmation.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -LocalFileSystemName "fs01" -RemoteName "remote-fb"
        Attaches the policy, scoping the request to the replica link whose remote array is "remote-fb".
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [Alias('MemberName')] [string]$LocalFileSystemName,
        [Parameter()] [string]$LocalFileSystemId,
        [Parameter()] [string]$MemberId,
        [Parameter()] [string]$RemoteId,
        [Parameter()] [string]$RemoteName,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('PolicyName'))           { $queryParams['policy_names']            = $PolicyName }
    if ($PSBoundParameters.ContainsKey('PolicyId'))             { $queryParams['policy_ids']              = $PolicyId }
    if ($PSBoundParameters.ContainsKey('LocalFileSystemName'))  { $queryParams['local_file_system_names'] = $LocalFileSystemName }
    if ($PSBoundParameters.ContainsKey('LocalFileSystemId'))    { $queryParams['local_file_system_ids']   = $LocalFileSystemId }
    if ($PSBoundParameters.ContainsKey('MemberId'))             { $queryParams['member_ids']              = $MemberId }
    if ($PSBoundParameters.ContainsKey('RemoteId'))             { $queryParams['remote_ids']              = $RemoteId }
    if ($PSBoundParameters.ContainsKey('RemoteName'))           { $queryParams['remote_names']            = $RemoteName }

    $target = if ($LocalFileSystemName) { $LocalFileSystemName } elseif ($LocalFileSystemId) { $LocalFileSystemId } else { $MemberId }
    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess("$target", "Attach policy '$policy' to replica link")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams
    }
}
