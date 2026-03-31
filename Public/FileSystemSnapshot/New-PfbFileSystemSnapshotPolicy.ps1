function New-PfbFileSystemSnapshotPolicy {
    <#
    .SYNOPSIS
        Attaches a policy to a file system snapshot on the FlashBlade.
    .DESCRIPTION
        Associates an existing policy with a file system snapshot by specifying
        both the policy and snapshot names or IDs.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER MemberName
        The name of the snapshot to attach the policy to.
    .PARAMETER MemberId
        The ID of the snapshot to attach the policy to.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly" -MemberName "fs01.snap1"
        Attaches the 'replication-hourly' policy to snapshot 'fs01.snap1'.
    .EXAMPLE
        New-PfbFileSystemSnapshotPolicy -PolicyId "abc-123" -MemberId "def-456"
        Attaches a policy to a snapshot using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names']  = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']    = $MemberId }

    $target = if ($MemberName) { $MemberName } else { $MemberId }
    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess("$target", "Attach policy '$policy'")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots/policies' -QueryParams $queryParams
    }
}
