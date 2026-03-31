function Get-PfbTlsPolicy {
    <#
    .SYNOPSIS
        Retrieves TLS policies from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbTlsPolicy cmdlet returns TLS policy configurations from the connected
        Pure Storage FlashBlade. TLS policies define the minimum TLS version and allowed
        cipher suites for secure communications.
    .PARAMETER Name
        One or more TLS policy names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more TLS policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbTlsPolicy

        Retrieves all TLS policies from the connected FlashBlade.
    .EXAMPLE
        Get-PfbTlsPolicy -Name "tls-strict"

        Retrieves the TLS policy named "tls-strict".
    .EXAMPLE
        Get-PfbTlsPolicy -Filter "min_version='1.2'" -Sort "name" -Limit 10

        Retrieves up to 10 TLS policies requiring TLS 1.2 minimum.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'tls-policies' -QueryParams $queryParams -AutoPaginate
    }
}
