function Get-PfbNetworkInterfaceConnectorSettings {
    <#
    .SYNOPSIS
        Retrieves settings for FlashBlade network interface connectors.
    .DESCRIPTION
        The Get-PfbNetworkInterfaceConnectorSettings cmdlet returns the read-only configuration
        settings for network interface connectors on the connected Pure Storage FlashBlade.
        This includes information such as speed capabilities and supported modes.
    .PARAMETER Name
        One or more connector names to retrieve settings for.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnectorSettings

        Retrieves settings for all network interface connectors.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnectorSettings -Name "CH1.FM1.ETH1"

        Retrieves settings for the specified connector.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnectorSettings -Filter "port_speed='40Gb/s'" -Limit 5

        Retrieves up to 5 connectors with 40Gb/s port speed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
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
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/connectors/settings' -QueryParams $queryParams -AutoPaginate
    }
}
