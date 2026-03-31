function New-PfbNetworkInterfaceTlsPolicy {
    <#
    .SYNOPSIS
        Associates a TLS policy with a FlashBlade network interface.
    .DESCRIPTION
        The New-PfbNetworkInterfaceTlsPolicy cmdlet creates an association between a network
        interface and a TLS policy on the connected Pure Storage FlashBlade. This controls
        the TLS settings used for connections on the specified interface.
    .PARAMETER MemberName
        The name of the network interface to associate with the TLS policy.
    .PARAMETER PolicyName
        The name of the TLS policy to apply to the network interface.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNetworkInterfaceTlsPolicy -MemberName "data-vip1" -PolicyName "strict-tls-1.3"

        Associates the strict-tls-1.3 policy with the data-vip1 network interface.
    .EXAMPLE
        New-PfbNetworkInterfaceTlsPolicy -MemberName "mgmt-vip" -PolicyName "default-tls" -WhatIf

        Shows what would happen without applying the TLS policy association.
    .EXAMPLE
        New-PfbNetworkInterfaceTlsPolicy -MemberName "repl-vip1" -PolicyName "tls-1.2-compat"

        Associates the tls-1.2-compat policy with the repl-vip1 interface.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Add TLS policy to network interface')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-interfaces/tls-policies' -QueryParams $queryParams
    }
}
