function New-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Attaches a policy to a file system replica link on the FlashBlade.
    .DESCRIPTION
        Associates an existing policy with a file system replica link by specifying
        both the policy and replica link (member) names or IDs.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER MemberName
        The name of the replica link to attach the policy to.
    .PARAMETER MemberId
        The ID of the replica link to attach the policy to.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -MemberName "fs01"
        Attaches the 'repl-daily' policy to the replica link for 'fs01'.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyId "abc-123" -MemberId "def-456"
        Attaches a policy to a replica link using IDs.
    .EXAMPLE
        New-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-hourly" -MemberName "fs02" -Confirm:$false
        Attaches the policy without prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess("$target", "Attach policy '$policy' to replica link")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams
    }
}
