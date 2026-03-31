function New-PfbQosPolicyMember {
    <#
    .SYNOPSIS
        Adds a member to a QoS policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbQosPolicyMember cmdlet associates a file system or bucket with a QoS
        policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The QoS policy name.
    .PARAMETER PolicyId
        The QoS policy ID.
    .PARAMETER MemberName
        The member name to add to the policy.
    .PARAMETER MemberId
        The member ID to add to the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQosPolicyMember -PolicyName "qos-gold" -MemberName "fs1"

        Associates "fs1" with the QoS policy "qos-gold".
    .EXAMPLE
        New-PfbQosPolicyMember -PolicyName "qos-gold" -MemberName "bucket1" -WhatIf

        Shows what would happen without actually adding the member.
    .EXAMPLE
        New-PfbQosPolicyMember -PolicyName "qos-silver" -MemberName "fs2"

        Associates "fs2" with the QoS policy "qos-silver".
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
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add QoS policy member')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'qos-policies/members' -QueryParams $queryParams
    }
}
