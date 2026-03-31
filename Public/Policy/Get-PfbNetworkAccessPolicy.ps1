function Get-PfbNetworkAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves network access policies from the FlashBlade.
    .DESCRIPTION
        Returns one or more network access policies from the FlashBlade array.
        Policies can be filtered by name, ID, or a server-side filter expression.
        Results can be sorted and limited. Supports pipeline input on Name.
    .PARAMETER Name
        One or more network access policy names to retrieve.
    .PARAMETER Id
        One or more network access policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkAccessPolicy

        Returns all network access policies.
    .EXAMPLE
        Get-PfbNetworkAccessPolicy -Name "net-access-01"

        Returns the network access policy named 'net-access-01'.
    .EXAMPLE
        "net-access-01", "net-access-02" | Get-PfbNetworkAccessPolicy

        Returns network access policies using pipeline input.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-access-policies' -QueryParams $queryParams -AutoPaginate
    }
}
