function Get-PfbArraySupportedTimeZone {
    <#
    .SYNOPSIS
        Retrieves supported time zones from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArraySupportedTimeZone cmdlet returns the list of supported time zones
        that can be configured on the connected Pure Storage FlashBlade. This is a read-only
        reference endpoint.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArraySupportedTimeZone

        Retrieves all supported time zones.
    .EXAMPLE
        Get-PfbArraySupportedTimeZone -Filter "name='America/*'"

        Retrieves supported time zones in the Americas.
    .EXAMPLE
        Get-PfbArraySupportedTimeZone -Sort "name" -Limit 20

        Retrieves up to 20 time zones sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/supported-time-zones' -QueryParams $queryParams -AutoPaginate
}
