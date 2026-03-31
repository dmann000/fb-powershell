function Remove-PfbFileSystemPolicy {
    <#
    .SYNOPSIS
        Detaches a policy from a file system on the FlashBlade.
    .DESCRIPTION
        Removes the association between a policy and a file system by specifying
        both the policy and file system names or IDs.
    .PARAMETER PolicyName
        The name of the policy to detach.
    .PARAMETER PolicyId
        The ID of the policy to detach.
    .PARAMETER MemberName
        The name of the file system to detach the policy from.
    .PARAMETER MemberId
        The ID of the file system to detach the policy from.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystemPolicy -PolicyName "snapshot-daily" -MemberName "fs01"
        Detaches the 'snapshot-daily' policy from file system 'fs01'.
    .EXAMPLE
        Remove-PfbFileSystemPolicy -PolicyId "abc-123" -MemberId "def-456"
        Detaches a policy from a file system using IDs.
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

    if ($PSCmdlet.ShouldProcess($target, 'Detach policy from file system')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/policies' -QueryParams $queryParams
    }
}
