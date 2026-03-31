function New-PfbAuditFileSystemPolicyMember {
    <#
    .SYNOPSIS
        Adds a file system as a member of an audit file-system policy.
    .DESCRIPTION
        The New-PfbAuditFileSystemPolicyMember cmdlet associates a file system with an audit
        file-system policy on the connected Pure Storage FlashBlade. Identify the policy and
        member by name or ID.
    .PARAMETER PolicyName
        The name of the audit file-system policy.
    .PARAMETER PolicyId
        The ID of the audit file-system policy.
    .PARAMETER MemberName
        The name of the file system to add as a member.
    .PARAMETER MemberId
        The ID of the file system to add as a member.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1" -MemberName "fs1"

        Adds file system "fs1" as a member of the audit file-system policy "audit-fs-pol1".
    .EXAMPLE
        New-PfbAuditFileSystemPolicyMember -PolicyId "abc-123" -MemberId "def-456"

        Adds a file system to the audit file-system policy using IDs.
    .EXAMPLE
        New-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1" -MemberName "fs1" -Confirm:$false

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

    if ($PSCmdlet.ShouldProcess($target, 'Add audit file-system policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'audit-file-systems-policies/members' -QueryParams $queryParams
    }
}
