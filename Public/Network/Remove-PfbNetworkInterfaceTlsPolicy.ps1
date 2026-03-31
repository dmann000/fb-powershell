function Remove-PfbNetworkInterfaceTlsPolicy {
    <#
    .SYNOPSIS
        Removes a TLS policy association from a FlashBlade network interface.
    .DESCRIPTION
        The Remove-PfbNetworkInterfaceTlsPolicy cmdlet deletes the association between a
        network interface and a TLS policy on the connected Pure Storage FlashBlade. This
        cmdlet has a high confirm impact and will prompt for confirmation by default.
    .PARAMETER MemberName
        The name of the network interface to disassociate from the TLS policy.
    .PARAMETER PolicyName
        The name of the TLS policy to remove from the network interface.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNetworkInterfaceTlsPolicy -MemberName "data-vip1" -PolicyName "strict-tls-1.3"

        Removes the TLS policy association after prompting for confirmation.
    .EXAMPLE
        Remove-PfbNetworkInterfaceTlsPolicy -MemberName "data-vip1" -PolicyName "old-policy" -Confirm:$false

        Removes the TLS policy association without prompting.
    .EXAMPLE
        Remove-PfbNetworkInterfaceTlsPolicy -MemberName "mgmt-vip" -PolicyName "deprecated-tls"

        Removes the deprecated TLS policy from the management VIP interface.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$MemberName,
        [Parameter(Mandatory)] [string]$PolicyName,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    $queryParams['member_names'] = $MemberName
    $queryParams['policy_names'] = $PolicyName

    $target = "${MemberName}:${PolicyName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove TLS policy from network interface')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'network-interfaces/tls-policies' -QueryParams $queryParams
    }
}
