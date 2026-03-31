function Remove-PfbFileSystemSnapshotPolicy {
    <#
    .SYNOPSIS
        Detaches a policy from a file system snapshot on the FlashBlade.
    .DESCRIPTION
        Removes the association between a policy and a file system snapshot by
        specifying both the policy and snapshot names or IDs.
    .PARAMETER PolicyName
        The name of the policy to detach.
    .PARAMETER PolicyId
        The ID of the policy to detach.
    .PARAMETER MemberName
        The name of the snapshot to detach the policy from.
    .PARAMETER MemberId
        The ID of the snapshot to detach the policy from.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotPolicy -PolicyName "replication-hourly" -MemberName "fs01.snap1"
        Detaches the 'replication-hourly' policy from snapshot 'fs01.snap1'.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotPolicy -PolicyId "abc-123" -MemberId "def-456"
        Detaches a policy from a snapshot using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Detach policy from snapshot')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-snapshots/policies' -QueryParams $queryParams
    }
}
