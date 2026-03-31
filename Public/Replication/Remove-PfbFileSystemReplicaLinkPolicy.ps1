function Remove-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Detaches a policy from a file system replica link on the FlashBlade.
    .DESCRIPTION
        Removes the association between a policy and a file system replica link by
        specifying both the policy and replica link (member) names or IDs.
    .PARAMETER PolicyName
        The name of the policy to detach.
    .PARAMETER PolicyId
        The ID of the policy to detach.
    .PARAMETER MemberName
        The name of the replica link to detach the policy from.
    .PARAMETER MemberId
        The ID of the replica link to detach the policy from.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -MemberName "fs01"
        Detaches the 'repl-daily' policy from the replica link for 'fs01'.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyId "abc-123" -MemberId "def-456"
        Detaches a policy from a replica link using IDs.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-hourly" -MemberName "fs02" -Confirm:$false
        Detaches the policy without prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess($target, 'Detach policy from replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams
    }
}
