function Get-PfbRealmSpace {
    <#
    .SYNOPSIS
        Retrieves realm space usage from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRealmSpace cmdlet returns space usage information for realms on the
        connected Pure Storage FlashBlade.
    .PARAMETER Name
        One or more realm names to retrieve space for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRealmSpace

        Retrieves space usage for all realms.
    .EXAMPLE
        Get-PfbRealmSpace -Name "realm-prod"

        Retrieves space usage for the specified realm.
    .EXAMPLE
        Get-PfbRealmSpace -Sort "space.total_physical-" -Limit 5

        Retrieves the top 5 realms by physical space usage.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'realms/space' -QueryParams $queryParams -AutoPaginate
    }
}
