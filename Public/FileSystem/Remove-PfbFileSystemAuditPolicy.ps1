function Remove-PfbFileSystemAuditPolicy {
    <#
    .SYNOPSIS
        Detaches an audit policy from a file system on the FlashBlade.
    .DESCRIPTION
        Removes the association between an audit policy and a file system by specifying
        both the policy and file system names or IDs.
    .PARAMETER PolicyName
        The name of the audit policy to detach.
    .PARAMETER PolicyId
        The ID of the audit policy to detach.
    .PARAMETER MemberName
        The name of the file system to detach the audit policy from.
    .PARAMETER MemberId
        The ID of the file system to detach the audit policy from.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemAuditPolicy -PolicyName "audit-all" -MemberName "fs01"
        Detaches the 'audit-all' audit policy from file system 'fs01'.
    .EXAMPLE
        Remove-PfbFileSystemAuditPolicy -PolicyId "abc-123" -MemberId "def-456"
        Detaches an audit policy from a file system using IDs.
    .EXAMPLE
        Remove-PfbFileSystemAuditPolicy -PolicyName "audit-writes" -MemberName "fs02" -Confirm:$false
        Detaches the audit policy without prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess($target, 'Detach audit policy from file system')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/audit-policies' -QueryParams $queryParams
    }
}
