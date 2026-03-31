function Get-PfbHardwareTemperature {
    <#
    .SYNOPSIS
        Retrieves temperature sensor data from FlashBlade hardware components.
    .DESCRIPTION
        The Get-PfbHardwareTemperature cmdlet returns temperature readings from hardware
        sensors on the connected Pure Storage FlashBlade. This includes current temperature
        values and sensor readings for monitoring purposes.

        This cmdlet queries the /hardware endpoint and filters to components that report
        temperature data. Each returned object includes the component name, status,
        temperature, and detailed sensor_readings when available.
    .PARAMETER Name
        One or more hardware component names to retrieve temperature data for.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbHardwareTemperature

        Retrieves temperature data for all hardware components that report temperature.
    .EXAMPLE
        Get-PfbHardwareTemperature -Name "CH1.FB1"

        Retrieves temperature data for the specified component.
    .EXAMPLE
        Get-PfbHardwareTemperature -Limit 5

        Retrieves temperature data for up to 5 components.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [int]$Limit,
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
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }

        $hardware = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'hardware' -QueryParams $queryParams -AutoPaginate

        # Filter to components that have temperature data
        $result = $hardware | Where-Object { $null -ne $_.temperature }

        if ($Limit -gt 0) {
            $result = $result | Select-Object -First $Limit
        }

        return $result
    }
}
