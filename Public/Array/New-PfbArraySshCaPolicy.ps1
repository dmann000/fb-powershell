function New-PfbArraySshCaPolicy {
    <#
    .SYNOPSIS
        Associates an SSH CA policy with an array on a FlashBlade.
    .DESCRIPTION
        The New-PfbArraySshCaPolicy cmdlet creates an association between an array and an
        SSH certificate authority policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The SSH CA policy name.
    .PARAMETER PolicyId
        The SSH CA policy ID.
    .PARAMETER MemberName
        The array name to associate with the policy.
    .PARAMETER MemberId
        The array ID to associate with the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArraySshCaPolicy -PolicyName "ssh-ca-prod" -MemberName "array1"

        Associates "array1" with the SSH CA policy "ssh-ca-prod".
    .EXAMPLE
        New-PfbArraySshCaPolicy -PolicyName "ssh-ca-prod" -MemberName "array2" -WhatIf

        Shows what would happen without actually creating the association.
    .EXAMPLE
        New-PfbArraySshCaPolicy -PolicyName "ssh-ca-dev" -MemberName "dev-array"

        Associates "dev-array" with the SSH CA policy "ssh-ca-dev".
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

    if ($PSCmdlet.ShouldProcess($target, 'Add array SSH CA policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'arrays/ssh-certificate-authority-policies' -QueryParams $queryParams
    }
}
