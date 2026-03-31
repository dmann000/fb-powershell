function Get-PfbArrayErasure {
    <#
    .SYNOPSIS
        Retrieves array erasure information from a FlashBlade.
    .DESCRIPTION
        The Get-PfbArrayErasure cmdlet returns array erasure job information from the connected
        Pure Storage FlashBlade. Erasure jobs securely wipe data from the array.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayErasure

        Retrieves all array erasure jobs from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayErasure -Filter "status='completed'"

        Retrieves completed erasure jobs.
    .EXAMPLE
        Get-PfbArrayErasure -Sort "name" -Limit 5

        Retrieves up to 5 erasure jobs sorted by name.
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
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/erasures' -QueryParams $queryParams -AutoPaginate
}
