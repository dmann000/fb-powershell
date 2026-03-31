function Get-PfbSoftwareCheck {
    <#
    .SYNOPSIS
        Retrieves software check results from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSoftwareCheck cmdlet returns pre-upgrade software check results from the
        connected Pure Storage FlashBlade, identifying potential issues before upgrading.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSoftwareCheck

        Retrieves all software check results from the connected FlashBlade.
    .EXAMPLE
        Get-PfbSoftwareCheck -Filter "status='critical'"

        Retrieves only critical software check results.
    .EXAMPLE
        Get-PfbSoftwareCheck -Sort "name" -Limit 10

        Retrieves up to 10 software check results sorted by name.
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
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'software-check' -QueryParams $queryParams -AutoPaginate
}
