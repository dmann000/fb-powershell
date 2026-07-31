function New-PfbFileSystemUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Attaches a user/group quota policy to a file system on a FlashBlade array.
    .DESCRIPTION
        The New-PfbFileSystemUserGroupQuotaPolicy cmdlet associates an existing
        user-group-quota policy with a file system, queried/invoked from the file-system side.
        Functionally identical to New-PfbUserGroupQuotaPolicyFileSystem.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER MemberName
        The name of the file system to attach the policy to.
    .PARAMETER MemberId
        The ID of the file system to attach the policy to.
    .PARAMETER DeleteExistingUserGroupQuotaSettings
        If set, deletes the file system's existing legacy purequota/purefs quota settings
        when attaching this policy.
    .PARAMETER IgnoreUsage
        If set, existing user/group usage on the file system is not checked against the
        policy's rules.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbFileSystemUserGroupQuotaPolicy -PolicyName "quota-pol-1" -MemberName "fs1"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [switch]$DeleteExistingUserGroupQuotaSettings,
        [Parameter()] [switch]$IgnoreUsage,
        [Parameter()] [PSCustomObject]$Array
    )

    if (-not $PolicyName -and -not $PolicyId) { throw 'You must supply either -PolicyName or -PolicyId.' }
    if (-not $MemberName -and -not $MemberId) { throw 'You must supply either -MemberName or -MemberId.' }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }
    if ($DeleteExistingUserGroupQuotaSettings) { $queryParams['delete_existing_user_group_quota_settings'] = 'true' }
    if ($IgnoreUsage) { $queryParams['ignore_usage'] = 'true' }

    $target = if ($MemberName) { $MemberName } else { $MemberId }
    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, "Attach user-group-quota policy '$policy'")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems/user-group-quota-policies' -QueryParams $queryParams
    }
}
