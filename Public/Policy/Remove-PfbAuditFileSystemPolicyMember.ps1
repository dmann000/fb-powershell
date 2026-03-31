function Remove-PfbAuditFileSystemPolicyMember {
    <#
    .SYNOPSIS
        Removes a file system from an audit file-system policy.
    .DESCRIPTION
        The Remove-PfbAuditFileSystemPolicyMember cmdlet removes the association between a
        file system and an audit file-system policy on the connected Pure Storage FlashBlade.
        This is a destructive operation and requires confirmation.
    .PARAMETER PolicyName
        The name of the audit file-system policy.
    .PARAMETER PolicyId
        The ID of the audit file-system policy.
    .PARAMETER MemberName
        The name of the file system to remove from the policy.
    .PARAMETER MemberId
        The ID of the file system to remove from the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1" -MemberName "fs1"

        Removes file system "fs1" from the audit file-system policy "audit-fs-pol1".
    .EXAMPLE
        Remove-PfbAuditFileSystemPolicyMember -PolicyId "abc-123" -MemberId "def-456"

        Removes the member association using IDs.
    .EXAMPLE
        Remove-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1" -MemberName "fs1" -Confirm:$false

        Removes the member without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [string]$PolicyName,

        [Parameter()]
        [string]$PolicyId,

        [Parameter()]
        [string]$MemberName,

        [Parameter()]
        [string]$MemberId,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove audit file-system policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'audit-file-systems-policies/members' -QueryParams $queryParams
    }
}
