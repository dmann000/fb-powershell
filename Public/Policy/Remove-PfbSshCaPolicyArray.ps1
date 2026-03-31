function Remove-PfbSshCaPolicyArray {
    <#
    .SYNOPSIS
        Removes an array from an SSH certificate authority policy on a FlashBlade.
    .DESCRIPTION
        The Remove-PfbSshCaPolicyArray cmdlet removes the association between an array and
        an SSH CA policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The SSH CA policy name.
    .PARAMETER PolicyId
        The SSH CA policy ID.
    .PARAMETER MemberName
        The array name to remove from the policy.
    .PARAMETER MemberId
        The array ID to remove from the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSshCaPolicyArray -PolicyName "ssh-ca-prod" -MemberName "array1"

        Removes "array1" from the SSH CA policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbSshCaPolicyArray -PolicyName "ssh-ca-prod" -MemberName "array2" -Confirm:$false

        Removes the array association without prompting.
    .EXAMPLE
        Remove-PfbSshCaPolicyArray -PolicyName "ssh-ca-test" -MemberName "test-array"

        Removes "test-array" from the SSH CA policy after prompting.
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove SSH CA policy array')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'ssh-certificate-authority-policies/arrays' -QueryParams $queryParams
    }
}
