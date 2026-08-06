function Get-PfbArrayPerformance {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array performance metrics.
    .DESCRIPTION
        Returns performance data including IOPS, throughput, and latency.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .PARAMETER Protocol
        Filter by protocol type: 'all', 'nfs', 'smb', 'http', 's3'. Defaults to 'all' (combined
        performance of all available protocols) when omitted.
    .PARAMETER Resolution
        Time resolution for historical data in milliseconds.
    .PARAMETER StartTime
        Start time for historical data (epoch milliseconds or datetime).
    .PARAMETER EndTime
        End time for historical data (epoch milliseconds or datetime).
    .EXAMPLE
        Get-PfbArrayPerformance
    .EXAMPLE
        Get-PfbArrayPerformance -Protocol nfs
    .NOTES
        <!-- PfbContext (generated; do not edit) -->
        Context requirement (GET /arrays/performance): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Array,

        [Parameter()]
        [ValidateSet('all', 'nfs', 'smb', 'http', 's3')]
        [string]$Protocol,

        [Parameter()]
        [int64]$Resolution,

        [Parameter()]
        [int64]$StartTime,

        [Parameter()]
        [int64]$EndTime
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Protocol)   { $queryParams['protocol']   = $Protocol }
    if ($Resolution) { $queryParams['resolution']  = $Resolution }
    if ($StartTime)  { $queryParams['start_time']  = $StartTime }
    if ($EndTime)    { $queryParams['end_time']    = $EndTime }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance' -QueryParams $queryParams -AutoPaginate
}
