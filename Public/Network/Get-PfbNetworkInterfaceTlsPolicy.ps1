function Get-PfbNetworkInterfaceTlsPolicy {
    <#
    .SYNOPSIS
        Retrieves TLS policy associations for FlashBlade network interfaces.
    .DESCRIPTION
        The Get-PfbNetworkInterfaceTlsPolicy cmdlet returns the associations between network
        interfaces and TLS policies on the connected Pure Storage FlashBlade. Results can be
        filtered by member name (interface) or policy name.
    .PARAMETER MemberName
        One or more network interface names to filter by.
    .PARAMETER MemberId
        One or more network interface IDs to filter by.
    .PARAMETER PolicyName
        One or more TLS policy names to filter by.
    .PARAMETER PolicyId
        One or more TLS policy IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkInterfaceTlsPolicy

        Retrieves all network interface TLS policy associations.
    .EXAMPLE
        Get-PfbNetworkInterfaceTlsPolicy -MemberName "data-vip1"

        Retrieves TLS policies associated with the specified network interface.
    .EXAMPLE
        Get-PfbNetworkInterfaceTlsPolicy -PolicyName "strict-tls-1.3"

        Retrieves all interfaces associated with the specified TLS policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
    if ($Filter)     { $queryParams['filter']       = $Filter }
    if ($Sort)       { $queryParams['sort']         = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/tls-policies' -QueryParams $queryParams -AutoPaginate
}
