function Get-PfbQosPolicyFileSystem {
    <#
    .SYNOPSIS
        Retrieves QoS policy file system associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbQosPolicyFileSystem cmdlet returns the cross-reference between QoS policies
        and file systems on the connected Pure Storage FlashBlade. This is a read-only view.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more file system names to filter by.
    .PARAMETER MemberId
        One or more file system IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbQosPolicyFileSystem

        Retrieves all QoS policy file system associations.
    .EXAMPLE
        Get-PfbQosPolicyFileSystem -PolicyName "qos-gold"

        Retrieves file system associations for the specified QoS policy.
    .EXAMPLE
        Get-PfbQosPolicyFileSystem -MemberName "fs1" -Limit 5

        Retrieves up to 5 QoS policy associations for the specified file system.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'qos-policies/file-systems' -QueryParams $queryParams -AutoPaginate
}
