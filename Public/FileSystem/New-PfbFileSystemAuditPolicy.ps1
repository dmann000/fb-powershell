function New-PfbFileSystemAuditPolicy {
    <#
    .SYNOPSIS
        Attaches an audit policy to a file system on the FlashBlade.
    .DESCRIPTION
        Associates an existing audit policy with a file system by specifying both
        the policy and file system names or IDs.
    .PARAMETER PolicyName
        The name of the audit policy to attach.
    .PARAMETER PolicyId
        The ID of the audit policy to attach.
    .PARAMETER MemberName
        The name of the file system to attach the audit policy to.
    .PARAMETER MemberId
        The ID of the file system to attach the audit policy to.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystemAuditPolicy -PolicyName "audit-all" -MemberName "fs01"
        Attaches the 'audit-all' audit policy to file system 'fs01'.
    .EXAMPLE
        New-PfbFileSystemAuditPolicy -PolicyId "abc-123" -MemberId "def-456"
        Attaches an audit policy to a file system using IDs.
    .EXAMPLE
        New-PfbFileSystemAuditPolicy -PolicyName "audit-writes" -MemberName "fs02" -Confirm:$false
        Attaches the policy without prompting for confirmation.
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
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names']  = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']    = $MemberId }

    $target = if ($MemberName) { $MemberName } else { $MemberId }
    $policy = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess("$target", "Attach audit policy '$policy'")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems/audit-policies' -QueryParams $queryParams
    }
}
