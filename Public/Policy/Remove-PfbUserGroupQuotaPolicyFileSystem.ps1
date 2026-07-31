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

    if (-not $PolicyName -and -not $PolicyId) {
        throw 'You must supply either -PolicyName or -PolicyId.'
    }
    if (-not $MemberName -and -not $MemberId) {
        throw 'You must supply either -MemberName or -MemberId.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }
    $member = if ($MemberName) { $MemberName } else { $MemberId }

    if ($PSCmdlet.ShouldProcess("${target}:${member}", 'Detach user-group-quota policy from file system')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'user-group-quota-policies/file-systems' -QueryParams $queryParams
    }
}
