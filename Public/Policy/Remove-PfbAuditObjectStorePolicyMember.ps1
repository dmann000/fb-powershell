function Remove-PfbAuditObjectStorePolicyMember {
    <#
    .SYNOPSIS
        Removes a member from an audit object-store policy.
    .DESCRIPTION
        The Remove-PfbAuditObjectStorePolicyMember cmdlet removes the association between an
        object-store account and an audit object-store policy on the connected Pure Storage
        FlashBlade. This is a destructive operation and requires confirmation.
    .PARAMETER PolicyName
        The name of the audit object-store policy.
    .PARAMETER PolicyId
        The ID of the audit object-store policy.
    .PARAMETER MemberName
        The name of the object-store account to remove from the policy.
    .PARAMETER MemberId
        The ID of the object-store account to remove from the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1" -MemberName "account1"

        Removes "account1" from the audit object-store policy "audit-obj-pol1".
    .EXAMPLE
        Remove-PfbAuditObjectStorePolicyMember -PolicyId "abc-123" -MemberId "def-456"

        Removes the member association using IDs.
    .EXAMPLE
        Remove-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1" -MemberName "account1" -Confirm:$false

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

    if ($PSCmdlet.ShouldProcess($target, 'Remove audit object-store policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'audit-object-store-policies/members' -QueryParams $queryParams
    }
}
