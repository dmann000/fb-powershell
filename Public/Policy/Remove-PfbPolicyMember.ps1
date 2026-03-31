function Remove-PfbPolicyMember {
    <#
    .SYNOPSIS
        Removes a file system from a policy.
    .PARAMETER PolicyName
        The policy name.
    .PARAMETER PolicyId
        The policy ID.
    .PARAMETER MemberName
        The file system name to remove.
    .PARAMETER MemberId
        The file system ID to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbPolicyMember -PolicyName "daily-snap" -MemberName "fs1"
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'policies/members' -QueryParams $queryParams
    }
}
