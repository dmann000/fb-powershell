function Remove-PfbUserGroupQuotaPolicyFileSystem {
    <#
    .SYNOPSIS
        Detaches a user/group quota policy from a file system on a FlashBlade array.
    .PARAMETER PolicyName
        The name of the policy to detach.
    .PARAMETER PolicyId
        The ID of the policy to detach.
    .PARAMETER MemberName
        The name of the file system to detach the policy from.
    .PARAMETER MemberId
        The ID of the file system to detach the policy from.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbUserGroupQuotaPolicyFileSystem -PolicyName "quota-pol-1" -MemberName "fs1"
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
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Detach user-group-quota policy from file system')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'user-group-quota-policies/file-systems' -QueryParams $queryParams
    }
}
