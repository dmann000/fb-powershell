function Get-PfbFleetKey {
    <#
    .SYNOPSIS
        Retrieves fleet keys from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFleetKey cmdlet returns fleet key information from the connected Pure Storage
        FlashBlade. Fleet keys are used to authenticate fleet member enrollment. Results can be
        filtered by name or a server-side filter expression.
    .PARAMETER Name
        One or more fleet names to retrieve keys for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFleetKey

        Retrieves all fleet keys from the connected FlashBlade.
    .EXAMPLE
        Get-PfbFleetKey -Name "fleet-prod"

        Retrieves the fleet key for the fleet named "fleet-prod".
    .EXAMPLE
        Get-PfbFleetKey -Filter "name='fleet*'" -Limit 5

        Retrieves up to 5 fleet keys matching the filter.
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
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'fleets/fleet-key' -QueryParams $queryParams -AutoPaginate
    }
}
