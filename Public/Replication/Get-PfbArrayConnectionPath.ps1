function Get-PfbArrayConnectionPath {
    <#
    .SYNOPSIS
        Retrieves array connection path information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionPath cmdlet returns network path information for array
        connections on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        One or more connection names to retrieve paths for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionPath

        Retrieves all array connection paths from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnectionPath -Name "remote-fb-dc2"

        Retrieves connection paths for the specified array connection.
    .EXAMPLE
        Get-PfbArrayConnectionPath -Limit 10

        Retrieves up to 10 array connection paths.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/path' -QueryParams $queryParams -AutoPaginate
    }
}
