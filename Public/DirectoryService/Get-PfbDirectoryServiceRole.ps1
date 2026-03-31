function Get-PfbDirectoryServiceRole {
    <#
    .SYNOPSIS
        Retrieves FlashBlade directory service roles.
    .DESCRIPTION
        The Get-PfbDirectoryServiceRole cmdlet returns one or more directory service roles from
        the connected Pure Storage FlashBlade. Results can be filtered by name, ID, or a
        server-side filter expression. Supports pipeline input for batch lookups and automatic
        pagination.
    .PARAMETER Name
        One or more directory service role names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more directory service role IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "name='ad-admins'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbDirectoryServiceRole

        Retrieves all directory service roles from the connected FlashBlade.
    .EXAMPLE
        Get-PfbDirectoryServiceRole -Name "ad-admins"

        Retrieves the directory service role named "ad-admins".
    .EXAMPLE
        Get-PfbDirectoryServiceRole -Filter "name='*ops*'" -Limit 10

        Retrieves up to 10 directory service roles matching the filter.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/roles' -QueryParams $queryParams -AutoPaginate
    }
}
