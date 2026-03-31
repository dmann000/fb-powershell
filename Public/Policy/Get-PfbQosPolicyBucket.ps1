function Get-PfbQosPolicyBucket {
    <#
    .SYNOPSIS
        Retrieves QoS policy bucket associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbQosPolicyBucket cmdlet returns the cross-reference between QoS policies
        and buckets on the connected Pure Storage FlashBlade. This is a read-only view.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more bucket names to filter by.
    .PARAMETER MemberId
        One or more bucket IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbQosPolicyBucket

        Retrieves all QoS policy bucket associations.
    .EXAMPLE
        Get-PfbQosPolicyBucket -PolicyName "qos-gold"

        Retrieves bucket associations for the specified QoS policy.
    .EXAMPLE
        Get-PfbQosPolicyBucket -MemberName "my-bucket" -Limit 5

        Retrieves up to 5 QoS policy associations for the specified bucket.
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'qos-policies/buckets' -QueryParams $queryParams -AutoPaginate
}
