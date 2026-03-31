function Remove-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Removes a policy from a file system replica link on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbPolicyFileSystemReplicaLink cmdlet removes the association between a
        policy and a file system replica link on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The policy name.
    .PARAMETER PolicyId
        The policy ID.
    .PARAMETER MemberName
        The file system replica link name.
    .PARAMETER MemberId
        The file system replica link ID.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberName "fs1/remote-fb"

        Removes the policy association after prompting for confirmation.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberName "fs1/remote-fb" -Confirm:$false

        Removes the association without prompting.
    .EXAMPLE
        Remove-PfbPolicyFileSystemReplicaLink -PolicyName "old-snap" -MemberName "fs2/remote-fb"

        Removes the old snapshot policy from the replica link.
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
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove policy from file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams
    }
}
