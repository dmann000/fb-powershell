function Get-PfbArrayConnectionKey {
    <#
    .SYNOPSIS
        Retrieves array connection keys from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionKey cmdlet returns array connection key information from
        the connected Pure Storage FlashBlade. Connection keys are used to authenticate
        array-to-array replication connections.
    .PARAMETER Name
        One or more connection names to retrieve keys for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionKey

        Retrieves all array connection keys from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnectionKey -Name "remote-fb-dc2"

        Retrieves the connection key for the specified array connection.
    .EXAMPLE
        Get-PfbArrayConnectionKey -Limit 5

        Retrieves up to 5 array connection keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
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
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/connection-key' -QueryParams $queryParams -AutoPaginate
    }
}
