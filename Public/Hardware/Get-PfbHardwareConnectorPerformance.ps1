function Get-PfbHardwareConnectorPerformance {
    <#
    .SYNOPSIS
        Retrieves performance metrics for FlashBlade hardware connectors.
    .DESCRIPTION
        The Get-PfbHardwareConnectorPerformance cmdlet returns performance data for hardware
        connectors on the connected Pure Storage FlashBlade. This includes throughput and
        error counters. Results can be scoped to a time range with optional resolution.
    .PARAMETER Name
        One or more connector names to retrieve performance data for.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER StartTime
        Start time for historical data in epoch milliseconds.
    .PARAMETER EndTime
        End time for historical data in epoch milliseconds.
    .PARAMETER Resolution
        Time resolution for historical data in milliseconds.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbHardwareConnectorPerformance

        Retrieves current performance data for all hardware connectors.
    .EXAMPLE
        Get-PfbHardwareConnectorPerformance -Name "CH1.FM1.ETH1"

        Retrieves performance data for the specified hardware connector.
    .EXAMPLE
        Get-PfbHardwareConnectorPerformance -StartTime 1700000000000 -EndTime 1700086400000 -Resolution 3600000

        Retrieves historical performance data at one-hour resolution for the specified time range.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }
    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($StartTime)            { $queryParams['start_time'] = $StartTime }
        if ($EndTime)              { $queryParams['end_time']   = $EndTime }
        if ($Resolution)           { $queryParams['resolution'] = $Resolution }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'hardware-connectors/performance' -QueryParams $queryParams -AutoPaginate
    }
}
