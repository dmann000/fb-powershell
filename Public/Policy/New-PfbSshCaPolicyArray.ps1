function New-PfbSshCaPolicyArray {
    <#
    .SYNOPSIS
        Adds an array to an SSH certificate authority policy on a FlashBlade.
    .DESCRIPTION
        The New-PfbSshCaPolicyArray cmdlet associates an array with an SSH CA policy
        on the connected Pure Storage FlashBlade.
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
        New-PfbSshCaPolicyArray -PolicyName "ssh-ca-prod" -MemberName "array1"

        Associates "array1" with the SSH CA policy "ssh-ca-prod".
    .EXAMPLE
        New-PfbSshCaPolicyArray -PolicyName "ssh-ca-prod" -MemberName "array2" -WhatIf

        Shows what would happen without actually adding the array.
    .EXAMPLE
        New-PfbSshCaPolicyArray -PolicyName "ssh-ca-dev" -MemberName "dev-array"

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

    if ($PSCmdlet.ShouldProcess($target, 'Add SSH CA policy array')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'ssh-certificate-authority-policies/arrays' -QueryParams $queryParams
    }
}
