function Get-PfbLog {
    <#
    .SYNOPSIS
        Retrieves log entries from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbLog cmdlet returns log entries from the connected Pure Storage FlashBlade.
        Results can be narrowed using a server-side filter expression and sorted or limited
        as needed.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "severity='warning'").
    .PARAMETER Sort
        Sort field and direction (e.g., "time" or "time-").
    .PARAMETER Limit
        Maximum number of log entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbLog

        Retrieves all log entries from the connected FlashBlade.
    .EXAMPLE
        Get-PfbLog -Limit 50

        Retrieves up to 50 log entries.
    .EXAMPLE
        Get-PfbLog -Filter "severity='error'" -Sort "time-" -Limit 20

        Retrieves up to 20 error-level log entries sorted by most recent first.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [long]$StartTime = [long]((Get-Date).AddHours(-1).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds,
        [Parameter()] [long]$EndTime = [long]((Get-Date).ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    $queryParams['start_time'] = $StartTime
    $queryParams['end_time'] = $EndTime
    if ($Filter)     { $queryParams['filter'] = $Filter }
    if ($Sort)       { $queryParams['sort']   = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'logs' -QueryParams $queryParams -AutoPaginate
}
