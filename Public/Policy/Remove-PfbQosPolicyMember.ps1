function Remove-PfbQosPolicyMember {
    <#
    .SYNOPSIS
        Removes a member from a QoS policy on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbQosPolicyMember cmdlet removes the association between a member (file
        system or bucket) and a QoS policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The QoS policy name.
    .PARAMETER PolicyId
        The QoS policy ID.
    .PARAMETER MemberName
        The member name to remove from the policy.
    .PARAMETER MemberId
        The member ID to remove from the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQosPolicyMember -PolicyName "qos-gold" -MemberName "fs1"

        Removes "fs1" from the QoS policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbQosPolicyMember -PolicyName "qos-gold" -MemberName "bucket1" -Confirm:$false

        Removes the member without prompting.
    .EXAMPLE
        Remove-PfbQosPolicyMember -PolicyName "qos-silver" -MemberName "fs-old"

        Removes "fs-old" from the QoS policy after prompting.
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
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove QoS policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'qos-policies/members' -QueryParams $queryParams
    }
}
