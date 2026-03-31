function Get-PfbApiClient {
    <#
    .SYNOPSIS
        Retrieves API clients from the FlashBlade.
    .DESCRIPTION
        The Get-PfbApiClient cmdlet returns API client configurations from the connected
        Pure Storage FlashBlade. API clients define the public key and access policies used
        for OAuth2 programmatic authentication. Results support filtering, sorting, and pagination.
    .PARAMETER Name
        One or more API client names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more API client IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbApiClient

        Returns all API clients configured on the connected FlashBlade.
    .EXAMPLE
        Get-PfbApiClient -Name 'automation-client'

        Retrieves the API client named 'automation-client'.
    .EXAMPLE
        Get-PfbApiClient -Filter "enabled='true'" -Limit 10

        Retrieves up to 10 enabled API clients.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']    = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'api-clients' -QueryParams $queryParams -AutoPaginate
    }
}
