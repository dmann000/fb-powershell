function New-PfbFileSystemPolicy {
    <#
    .SYNOPSIS
        Attaches a policy to a file system on the FlashBlade.
    .DESCRIPTION
        Associates an existing policy with a file system by specifying both
        the policy and file system names or IDs.
    .PARAMETER PolicyName
        The name of the policy to attach.
    .PARAMETER PolicyId
        The ID of the policy to attach.
    .PARAMETER MemberName
        The name of the file system to attach the policy to.
    .PARAMETER MemberId
        The ID of the file system to attach the policy to.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbFileSystemPolicy -PolicyName "snapshot-daily" -MemberName "fs01"
        Attaches the 'snapshot-daily' policy to file system 'fs01'.
    .EXAMPLE
        New-PfbFileSystemPolicy -PolicyId "abc-123" -MemberId "def-456"
        Attaches a policy to a file system using IDs.
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

    if ($PSCmdlet.ShouldProcess("$target", "Attach policy '$policy'")) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems/policies' -QueryParams $queryParams
    }
}
