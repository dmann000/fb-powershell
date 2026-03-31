function New-PfbAuditObjectStorePolicyMember {
    <#
    .SYNOPSIS
        Adds a member to an audit object-store policy.
    .DESCRIPTION
        The New-PfbAuditObjectStorePolicyMember cmdlet associates an object-store account
        with an audit object-store policy on the connected Pure Storage FlashBlade. Identify
        the policy and member by name or ID.
    .PARAMETER PolicyName
        The name of the audit object-store policy.
    .PARAMETER PolicyId
        The ID of the audit object-store policy.
    .PARAMETER MemberName
        The name of the object-store account to add as a member.
    .PARAMETER MemberId
        The ID of the object-store account to add as a member.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1" -MemberName "account1"

        Adds "account1" as a member of the audit object-store policy "audit-obj-pol1".
    .EXAMPLE
        New-PfbAuditObjectStorePolicyMember -PolicyId "abc-123" -MemberId "def-456"

        Adds a member to the audit object-store policy using IDs.
    .EXAMPLE
        New-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1" -MemberName "account1" -Confirm:$false

        Adds the member without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Add audit object-store policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'audit-object-store-policies/members' -QueryParams $queryParams
    }
}
