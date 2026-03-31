function Remove-PfbArraySshCaPolicy {
    <#
    .SYNOPSIS
        Removes an SSH CA policy association from an array on a FlashBlade.
    .DESCRIPTION
        The Remove-PfbArraySshCaPolicy cmdlet removes the association between an array and
        an SSH certificate authority policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The SSH CA policy name.
    .PARAMETER PolicyId
        The SSH CA policy ID.
    .PARAMETER MemberName
        The array name to disassociate.
    .PARAMETER MemberId
        The array ID to disassociate.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbArraySshCaPolicy -PolicyName "ssh-ca-prod" -MemberName "array1"

        Removes the SSH CA policy association after prompting for confirmation.
    .EXAMPLE
        Remove-PfbArraySshCaPolicy -PolicyName "ssh-ca-prod" -MemberName "array2" -Confirm:$false

        Removes the association without prompting.
    .EXAMPLE
        Remove-PfbArraySshCaPolicy -PolicyName "ssh-ca-test" -MemberName "test-array"

        Removes the association after prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove array SSH CA policy')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'arrays/ssh-certificate-authority-policies' -QueryParams $queryParams
    }
}
