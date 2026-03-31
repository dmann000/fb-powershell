function New-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Associates a policy with a file system replica link on a FlashBlade array.
    .DESCRIPTION
        The New-PfbPolicyFileSystemReplicaLink cmdlet creates an association between a policy
        and a file system replica link on the connected Pure Storage FlashBlade.
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
        New-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberName "fs1/remote-fb"

        Associates the policy with the replica link.
    .EXAMPLE
        New-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -MemberName "fs1/remote-fb" -WhatIf

        Shows what would happen without actually creating the association.
    .EXAMPLE
        New-PfbPolicyFileSystemReplicaLink -PolicyName "hourly-snap" -MemberName "fs2/remote-fb"

        Associates the hourly snapshot policy with the specified replica link.
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
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add policy to file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams
    }
}
