function New-PfbNetworkInterfaceTlsPolicy {
    <#
    .SYNOPSIS
        Associates a TLS policy with a FlashBlade network interface.
    .DESCRIPTION
        The New-PfbNetworkInterfaceTlsPolicy cmdlet creates an association between a network
        interface and a TLS policy on the connected Pure Storage FlashBlade. This controls
        the TLS settings used for connections on the specified interface.
    .PARAMETER MemberName
        The name of the network interface to associate with the TLS policy. Sent as the
        `member_names` query parameter. Mutually exclusive with -MemberId in effect (the
        array rejects both being provided together), but both are declared as plain optional
        parameters so either alone resolves the target interface.
    .PARAMETER MemberId
        The ID of the network interface to associate with the TLS policy. Sent as the
        `member_ids` query parameter.
    .PARAMETER PolicyName
        The name of the TLS policy to apply to the network interface. Sent as the
        `policy_names` query parameter.
    .PARAMETER PolicyId
        The ID of the TLS policy to apply to the network interface. Sent as the `policy_ids`
        query parameter.
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
    .EXAMPLE
        New-PfbNetworkInterfaceTlsPolicy -MemberId "10314f42-020d-7080-8013-000ddt400012" -PolicyId "10314f42-020d-7080-8013-000ddt400099"

        Associates the TLS policy and network interface identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        # -MemberName/-MemberId and -PolicyName/-PolicyId are both plain optional parameters
        # rather than parameter sets: `POST /network-interfaces/tls-policies` documents that
        # member_ids/member_names (and policy_ids/policy_names) cannot be provided together,
        # but there is no request body here to multiply a selector axis against (constraint 4
        # is about the -Attributes axis, which this cmdlet does not have). Making either of
        # -MemberName/-MemberId mandatory would make the other permanently unusable, so both
        # stay optional -- the same shape already shipped on the sibling cmdlet
        # New-PfbQosPolicyMember.
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('MemberName')) { $queryParams['member_names'] = $MemberName }
    if ($PSBoundParameters.ContainsKey('MemberId'))   { $queryParams['member_ids']   = $MemberId }
    if ($PSBoundParameters.ContainsKey('PolicyName')) { $queryParams['policy_names'] = $PolicyName }
    if ($PSBoundParameters.ContainsKey('PolicyId'))   { $queryParams['policy_ids']   = $PolicyId }

    $memberTarget = if ($PSBoundParameters.ContainsKey('MemberName')) { $MemberName } else { $MemberId }
    $policyTarget = if ($PSBoundParameters.ContainsKey('PolicyName')) { $PolicyName } else { $PolicyId }
    $target = "${memberTarget}:${policyTarget}"

    if ($PSCmdlet.ShouldProcess($target, 'Add TLS policy to network interface')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-interfaces/tls-policies' -QueryParams $queryParams
    }
}
